// Certificate issuance module
module dev::certificate {

    use std::option;
    use std::option::Option;
    use std::signer;
    use std::string::{utf8, String};
    use std::vector;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_std::ed25519;
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account;
    use aptos_token_objects::royalty;
    use aptos_token_objects::collection::Collection;
    use aptos_token_objects::token;
    use aptos_token_objects::collection;
    use aptos_token_objects::royalty::{ create};
    use aptos_token_objects::token::{Token};

    // Error codes
    const E_NOT_ADMIN: u64 = 1;
    // Caller is not admin
    const E_ALREADY_HAVE_CERTIFICATE: u64 = 5;
    // Already have certificate
    const E_INVALID_SIGNATURE: u64 = 8;
    // Invalid signature
    const E_NONCE_ALREADY_USED: u64 = 9;
    // Nonce already used

    const ADMIN_ADDRESS: address = @dev; // Admin address
    const ROYALTY_NUMERATOR: u64 = 100;
    const ROYALTY_DENOMINATOR: u64 = 100;

    // Type definitions

    // User points system and capabilities
    struct M2LCoin has store {}

    struct MintStore has key { cap: coin::MintCapability<M2LCoin> }

    struct BurnStore has key { cap: coin::BurnCapability<M2LCoin> }

    struct FreezeStore has key { cap: coin::FreezeCapability<M2LCoin> }

    struct CertificateCollectionInfo has key {
        collection: Object<Collection>
    }

    // Admin public key for signature verification
    struct AdminPublicKey has key {
        public_key: ed25519::UnvalidatedPublicKey
    }

    // Nonce tracking to prevent replay attacks
    struct NonceTracker has key {
        used_nonces: SimpleMap<String, bool>
    }

    // Resource account for admin operations
    struct ResourceAccount has key {
        signer_cap: account::SignerCapability
    }

    // Course certificate NFT
    struct CourseCertificate has key, store, copy {
        token: Object<Token>,
        token_address: address,
        user: address,
        course_id: String
    }

    // User certificate record table
    struct UserCertificatesTable has key {
        certificates: SimpleMap<String, SimpleMap<address, CourseCertificate>> // course_id ->  user_id -> CourseCertificate
    }

    // Mint certificate event
    #[event]
    struct MintCertificateEvent has drop, store {
        course_id: String,
        recipient: address,
        token_id: address,
        timestamp: u64,
        points: u64,
        status: String, // started/completed
    }

    // Coin mint event
    #[event]
    struct CoinMintEvent has drop, store {
        recipient: address,
        amount: u64,
        timestamp: u64,
    }

    // Certificate transfer event
    #[event]
    struct CertificateTransferEvent has drop, store {
        course_id: String,
        from: address,
        to: address,
        token_id: address,
        timestamp: u64,
    }

    // Error event
    #[event]
    struct ErrorEvent has drop, store {
        error_code: u64,
        error_message: String,
        timestamp: u64,
    }
    // ================= Contract Interaction Part ====================
    // Initialize contract
    public entry fun initialize(admin: &signer, admin_public_key_bytes: vector<u8>) {
        assert!(is_admin(admin), E_NOT_ADMIN);
        
        let coin_name = utf8(b"m2l_coin");
        let coin_symbol = utf8(b"m2l");
        // Register coin
        let (burn, freeze, mint) =
            coin::initialize<M2LCoin>(admin, coin_name, coin_symbol, 8, false);
        // Store coin's mint, burn, freeze capabilities
        move_to(admin, MintStore { cap: mint });
        move_to(admin, BurnStore { cap: burn });
        move_to(admin, FreezeStore { cap: freeze });

        // Store admin public key for signature verification
        let public_key = ed25519::new_unvalidated_public_key_from_bytes(admin_public_key_bytes);
        move_to(admin, AdminPublicKey { 
            public_key 
        });
        // Initialize nonce tracker
        move_to(admin, NonceTracker {
            used_nonces: simple_map::new()
        });
        // Initialize certificatesTable
        move_to(admin, UserCertificatesTable{
            certificates: simple_map::new()
        });
        
        // Create resource account for admin operations
        let (resource_signer, signer_cap) = account::create_resource_account(admin, b"certificate_resource");
        move_to(admin, ResourceAccount {
            signer_cap
        });
        // Initialize nft - use resource account to create collection
        let royalt = option::some(create(1, 1, @dev));
        let collection_ref=  collection::create_unlimited_collection(
            &resource_signer,
            utf8(b"Move to learn course certificate collection"),
            utf8(b"MoveToLearnCourseCerification"),
            royalt,
            utf8(b"")
        );
        let collection_obj = object::object_from_constructor_ref<Collection>(&collection_ref);
        move_to(admin, CertificateCollectionInfo {
            collection: collection_obj
        });
        let token_ref = token::create_token_as_collection_owner(
            &resource_signer,
            collection_obj,
            utf8(b""),
            utf8(b""),
            royalt,
            utf8(b"")
        );
    }

    // Mint certificate and coins to user (called by user with admin signature)
    public entry fun mint_certificate_and_coins(
        user: &signer,
        course_id: String,
        course_name: String,
        coin_amount: u64,
        nonce: String,
        signature: vector<u8>
    ) acquires UserCertificatesTable, MintStore, AdminPublicKey, NonceTracker, CertificateCollectionInfo, ResourceAccount
    {
        let user_address = signer::address_of(user);

        // Verify signature
        verify_admin_signature(course_id, nonce, signature);
        if (has_certificate(user_address, course_id)) {
            assert!(false, E_ALREADY_HAVE_CERTIFICATE);
        };
        // Check and mark nonce as used
        let nonce_tracker = borrow_global_mut<NonceTracker>(@dev);
        if (nonce_tracker.used_nonces.contains_key(&nonce)) {
            assert!(false, E_NONCE_ALREADY_USED);
        };
        nonce_tracker.used_nonces.add(nonce, true);

        // Verify if user already has the course certificate

        // Start mint certificate event
        event::emit(MintCertificateEvent {
            course_id,
            recipient: user_address,
            token_id: @0x0, // Temporary address, will be updated later
            timestamp: aptos_framework::timestamp::now_seconds(),
            points: coin_amount,
            status: utf8(b"started"),
        });

        // Get resource account signer
        let resource_account = borrow_global<ResourceAccount>(@dev);
        let resource_signer = account::create_signer_with_capability(&resource_account.signer_cap);

        let royalty = royalty::create(1, 1, @dev);
        let royalty_option = option::some(royalty);
        let collection_info = borrow_global<CertificateCollectionInfo>(@dev);

        // Create token using resource account as collection owner
        let token_ref = token::create_token_as_collection_owner(
            &resource_signer,
            collection_info.collection,
            utf8(b"Move to Learn Course Certification Token"),
            concat_strings(utf8(b"Certificate of course: "), course_name),
            royalty_option,
            utf8(b"")
        );

        let token_obj = object::object_from_constructor_ref<Token>(&token_ref);
        let token_address = object::object_address(&token_obj);

        // Transfer token to user
        object::transfer(&resource_signer, token_obj, user_address);

        // Record certificate
        record_certificate_for_user(course_id, user_address, token_address);
        
        // Auto-register M2LCoin for user and mint coins
        if (coin_amount > 0) {
            // Ensure user is registered for M2LCoin
            if (!coin::is_account_registered<M2LCoin>(user_address)) {
                coin::register<M2LCoin>(user);
            };
            mint_coin_to_user(user_address, coin_amount);
        };
        event::emit(MintCertificateEvent {
            course_id,
            recipient: user_address,
            token_id: @0x0,
            timestamp: aptos_framework::timestamp::now_seconds(),
            points: coin_amount,
            status: utf8(b"completed"),
        });
    }

    // Record certificate for user (simplified version)
    fun record_certificate_for_user(
        course_id: String,
        user_address: address,
        token_address: address
    ) acquires UserCertificatesTable {
        let user_certs = borrow_global_mut<UserCertificatesTable>(@dev);
        if (!user_certs.certificates.contains_key(&course_id)) {
            user_certs.certificates.add(course_id, simple_map::new());
        };
        let user_cert_table = user_certs.certificates.borrow_mut(&course_id);
        
        // Create certificate record with actual token object
        user_cert_table.add(user_address, CourseCertificate {
            token: object::address_to_object<Token>(token_address),
            token_address,
            user: user_address,
            course_id
        });
    }

    // ========================== View Function Part ========================

    // View user's certificates
    #[view]
    public fun view_user_certificates(
        _user_address: address
    ): vector<Object<Token>> {
        // Note: SimpleMap doesn't support iteration like BigOrderedMap
        // This is a simplified version that returns empty for now
        // In a real implementation, you might need to track course IDs separately
        vector::empty<Object<Token>>()
    }

    // View user's coin balance
    #[view]
    public fun view_user_balance(user_address: address): u64 {
        coin::balance<M2LCoin>(user_address)
    }

    // Admin view certificate issuance situation
    #[view]
    public fun view_certificate_stats(
        _course: String
    ): vector<address> {
        // Note: SimpleMap doesn't support iteration like BigOrderedMap
        // This is a simplified version that returns empty for now
        vector::empty<address>()
    }

    // View coin total supply
    #[view]
    public fun view_total_coin_supply(): Option<u128> {
        coin::supply<M2LCoin>()
    }

    // ========================== Tool Function Part ========================
    // Determine if signer is admin
    public fun is_admin(admin: &signer): bool {
        signer::address_of(admin) == @dev
    }

    // Verify admin signature
    fun verify_admin_signature(
        course_id: String,
        nonce: String,
        signature: vector<u8>
    ) acquires AdminPublicKey {
        let admin_key_store = borrow_global<AdminPublicKey>(@dev);
        
        let message = concat_strings(concat_strings(course_id, utf8(b"_")), nonce);
        let message_bytes = message.bytes();
        let signature_obj = ed25519::new_signature_from_bytes(signature);
        let is_valid = ed25519::signature_verify_strict(
            &signature_obj,
            &admin_key_store.public_key,
            *message_bytes
        );
        
        if (!is_valid) {
            assert!(false, E_INVALID_SIGNATURE)
        };
    }

    // Mint coin to user account (called internally)
    fun mint_coin_to_user(
        recipient: address,
        amount: u64
    ) acquires MintStore {
        let mint_store = borrow_global<MintStore>(@dev);
        let coin = coin::mint(amount, &mint_store.cap);
        coin::deposit(recipient, coin);
        
        event::emit(CoinMintEvent {
            recipient,
            amount,
            timestamp: aptos_framework::timestamp::now_seconds(),
        });
    }

    // Check if user already has a certificate for a course
    fun has_certificate(user: address, course_id: String): bool acquires UserCertificatesTable {
        if (!exists<UserCertificatesTable>(@dev)) {
            return false
        };
        let course_user_certs_table = borrow_global<UserCertificatesTable>(@dev);
        if (!course_user_certs_table.certificates.contains_key(&course_id)) {
            return false
        };
        let user_cert_table = course_user_certs_table.certificates.borrow(&course_id);
        if (user_cert_table.contains_key(&user)) {
            return true
        };
        false
    }

    // Get course certificate token
    fun get_certificate_token(
        course_id: String,
        user_address: address
    ): CourseCertificate acquires UserCertificatesTable {
        let course_user_token_table = borrow_global<UserCertificatesTable>(@dev);
        let user_token_table = course_user_token_table.certificates.borrow(&course_id);
        *user_token_table.borrow(&user_address)
    }

    // String concatenation helper function
    fun concat_strings(str1: String, str2: String): String {
        let result = vector::empty<u8>();
        result.append(*str1.bytes());
        result.append(*str2.bytes());
        utf8(result)
    }
}
