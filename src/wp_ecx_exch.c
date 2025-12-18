/* wp_ecx_exch.c
 *
 * Copyright (C) 2006-2025 wolfSSL Inc.
 *
 * This file is part of wolfProvider.
 *
 * wolfProvider is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * wolfProvider is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with wolfProvider. If not, see <http://www.gnu.org/licenses/>.
 */

#include <openssl/err.h>
#include <openssl/proverr.h>
#include <openssl/core_dispatch.h>
#include <openssl/core_names.h>
#include <openssl/params.h>
#include <openssl/ec.h>
#include <openssl/evp.h>
#include <stdio.h>

#include <wolfprovider/settings.h>
#include <wolfprovider/alg_funcs.h>

#if defined(WP_HAVE_X25519) || defined(WP_HAVE_X448)

/** Common key agree function pointer. */
typedef int (*WP_ECX_AGREE)(void* private_key, void* public_key, byte* out,
    word32* outlen);

/**
 * Alternative ECDH key exchange context.
 */
typedef struct wp_EcxCtx {
    /** Provider context - useful for getting library context. */
    WOLFPROV_CTX* provCtx;

    /** Reference to our key. */
    wp_Ecx* key;
    /** Reference to peer's public key. */
    wp_Ecx* peer;
} wp_EcxCtx;


/**
 * Create a new base alt ECDH key exchange context object.
 *
 * @param [in] provCtx  Provider context.
 * @return  ECDH key exchange object on success.
 * @return  NULL on failure.
 */
static wp_EcxCtx* wp_ecx_newctx(WOLFPROV_CTX* provCtx)
{
    wp_EcxCtx* ctx = NULL;

    if (wolfssl_prov_is_running()) {
        ctx = OPENSSL_zalloc(sizeof(*ctx));
    }
    if (ctx != NULL) {
        ctx->provCtx = provCtx;
    }

    return ctx;
}

/**
 * Free the alt ECDH key exchange context object.
 *
 * @param [in, out] ctx  Alt ECDH key exchange context object.
 */
static void wp_ecx_freectx(wp_EcxCtx* ctx)
{
    if (ctx != NULL) {
        /* UNCONDITIONAL DEBUG: Always print to stderr */
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_freectx: Freeing X25519/X448 key exchange context\n");
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_freectx: ctx=%p, key=%p, peer=%p\n", 
                ctx, ctx->key, ctx->peer);
        fflush(stderr);
        
        wp_ecx_free(ctx->peer);
        wp_ecx_free(ctx->key);
        OPENSSL_free(ctx);
        
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_freectx: Context freed\n");
        fflush(stderr);
    }
}

/**
 * Duplicate an alt ECDH key exchange context object.
 *
 * @param [in] src  Alt ECDH key exchange context object.
 * @return  Alt ECDH key exchange context object on success.
 * @return  NULL on failure.
 */
static wp_EcxCtx* wp_ecx_dupctx(wp_EcxCtx* src)
{
    wp_EcxCtx* dst = NULL;

    if (wolfssl_prov_is_running()) {
        dst = OPENSSL_zalloc(sizeof(*dst));
    }
    if (dst != NULL) {
        int ok = 1;

        dst->provCtx = src->provCtx;
        if ((src->key != NULL) && (!wp_ecx_up_ref(src->key))) {
            ok = 0;
        }
        else {
            dst->key = src->key;
        }
        if (ok && (src->peer != NULL) && (!wp_ecx_up_ref(src->peer))) {
            ok = 0;
        }
        else {
            dst->peer = src->peer;
        }
        if (!ok) {
            wp_ecx_free(src->key);
            OPENSSL_free(dst);
            dst = NULL;
        }
    }

    return dst;
}

/**
 * Initialize the alt ECDH key exchange object with private key and parameters.
 *
 * @param [in, out] ctx     Alt ECDH key exchange context object.
 * @param [in, out] ecx     Alt EC key object. (Up referenced.)
 * @param [in]      params  Parameters like KDF info.
 * @return  1 on success.
 * @return  0 on failure.
 */
static int wp_ecx_init(wp_EcxCtx* ctx, wp_Ecx* ecx, const OSSL_PARAM params[])
{
    int ok = 1;

    WOLFPROV_ENTER(WP_LOG_COMP_X25519, "wp_ecx_init");
    fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: ENTER ctx=%p, ecx=%p\n", ctx, ecx);
    fflush(stderr);

    /* No settable parameters. */
    (void)params;

    if (!wolfssl_prov_is_running()) {
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: Provider not running!\n");
        fflush(stderr);
        ok = 0;
    }
    
    /* Debug key structure details */
    if (ok && ecx != NULL) {
        void* key_ptr = wp_ecx_get_key(ecx);
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: wp_ecx_get_key(ecx)=%p\n", key_ptr);
        fflush(stderr);
        
        /* Check if key is initialized by trying to export */
        if (key_ptr != NULL) {
            byte test_pub[CURVE25519_KEYSIZE];
            word32 test_len = CURVE25519_KEYSIZE;
            int test_rc = wc_curve25519_export_public_ex((curve25519_key*)key_ptr, test_pub, &test_len, EC25519_LITTLE_ENDIAN);
            fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: Key export test: rc=%d, len=%u\n", test_rc, test_len);
            if (test_rc == 0 && test_len == CURVE25519_KEYSIZE) {
                fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: Key appears initialized, last byte=0x%02x (MSB=%s)\n",
                        test_pub[CURVE25519_KEYSIZE - 1],
                        (test_pub[CURVE25519_KEYSIZE - 1] & 0x80) ? "SET" : "CLEAR");
            }
            fflush(stderr);
        }
    }
    
    if (ok && (ctx->key != ecx)) {
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: Replacing old key %p with new key %p\n", ctx->key, ecx);
        fflush(stderr);
        wp_ecx_free(ctx->key);
        ctx->key = NULL;
        if (!wp_ecx_up_ref(ecx)) {
            fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: wp_ecx_up_ref failed!\n");
            fflush(stderr);
            ok = 0;
        }
    }
    if (ok) {
        ctx->key = ecx;
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: Key set successfully, ctx->key=%p\n", ctx->key);
        fflush(stderr);
    }

    fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: EXIT returning %d\n", ok);
    fflush(stderr);
    WOLFPROV_LEAVE(WP_LOG_COMP_X25519, __FILE__ ":" WOLFPROV_STRINGIZE(__LINE__), ok);
    return ok;
}

/**
 * Set the peer's public key into the alt ECDH key exchange context object.
 *
 * @param [in, out] ctx   Alt ECDH key exchange context object.
 * @param [in, out] peer  Peer's public key in alt ECDH key object.
 *                        (Up referenced.)
 * @return 1 on success.
 * @return 0 on failure.
 */
static int wp_ecx_set_peer(wp_EcxCtx* ctx, wp_Ecx* peer)
{
    int ok = 1;

    WOLFPROV_ENTER(WP_LOG_COMP_X25519, "wp_ecx_set_peer");
    fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: ENTER ctx=%p, peer=%p\n", ctx, peer);
    fflush(stderr);

    if (!wolfssl_prov_is_running()) {
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Provider not running!\n");
        fflush(stderr);
        ok = 0;
    }

    /* Debug peer key structure details */
    if (ok && peer != NULL) {
        void* peer_key_ptr = wp_ecx_get_key(peer);
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: wp_ecx_get_key(peer)=%p\n", peer_key_ptr);
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Memory alignment - peer_key_ptr alignment=%zu\n",
                (size_t)peer_key_ptr % 8);  /* Check 8-byte alignment */
        fflush(stderr);
    }

    if (ok && (ctx->peer != peer)) {
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Replacing old peer %p with new peer %p\n", ctx->peer, peer);
        fflush(stderr);
        wp_ecx_free(ctx->peer);
        ctx->peer = NULL;
        if (!wp_ecx_up_ref(peer)) {
            fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: wp_ecx_up_ref failed!\n");
            fflush(stderr);
            ok = 0;
        }
    }
    
    /* Fix for error -199 (ECC_BAD_ARG_E): Ensure peer public key MSB is cleared (RFC 7748) */
    /* This is done here (not in derive) because: */
    /* 1. Fix once when peer is set, not on every derive call */
    /* 2. wp_ecx_set_peer bypasses wp_x25519_import_public which normally clears MSB */
    /* 3. OpenSSL's default provider clears MSB during import, we must do the same */
    /* 4. We clear MSB directly and re-import using wc_curve25519_import_public_ex (same as wp_x25519_import_public) */
    /* NOTE: This fix ONLY applies to X25519 (32-byte keys), NOT X448 (56-byte keys) */
    fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Fixing peer key MSB, peer=%p\n", peer);
    fflush(stderr);
#ifdef WP_HAVE_X25519
    if (ok && peer != NULL) {
        void* peer_key = wp_ecx_get_key(peer);
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Checking peer key for MSB fix, peer_key=%p\n", peer_key);
        fflush(stderr);
        if (peer_key != NULL) {
            byte peer_pub[CURVE25519_KEYSIZE];
            word32 peer_pub_len = CURVE25519_KEYSIZE;
            int rc;
            
            /* Try to export as X25519 - if successful and size is 32, it's X25519 */
            /* If this fails or returns wrong size, it's X448 and we skip the MSB fix */
            fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Attempting to export peer key as X25519\n");
            fflush(stderr);
            rc = wc_curve25519_export_public_ex((curve25519_key*)peer_key, peer_pub, &peer_pub_len, EC25519_LITTLE_ENDIAN);
            fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Export result: rc=%d, peer_pub_len=%u (expected %d)\n", 
                    rc, peer_pub_len, CURVE25519_KEYSIZE);
            fflush(stderr);
            if (rc == 0 && peer_pub_len == CURVE25519_KEYSIZE) {
                /* This is X25519 - always normalize the key by re-importing */
                /* Even if exported bytes show MSB clear, the internal representation */
                /* might have MSB set, which causes wc_curve25519_shared_secret to fail */
                fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Confirmed X25519 key, normalizing MSB. Last byte=0x%02x\n", 
                        peer_pub[CURVE25519_KEYSIZE - 1]);
                fflush(stderr);
                /* Always clear MSB and re-import to ensure internal representation is correct */
                /* This matches wp_x25519_import_public behavior */
                peer_pub[CURVE25519_KEYSIZE - 1] &= 0x7f;
                fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: After MSB normalization, last byte=0x%02x\n", 
                        peer_pub[CURVE25519_KEYSIZE - 1]);
                fflush(stderr);
                /* Re-import using wc_curve25519_import_public_ex to normalize internal state */
                rc = wc_curve25519_import_public_ex(peer_pub, CURVE25519_KEYSIZE, (curve25519_key*)peer_key, EC25519_LITTLE_ENDIAN);
                if (rc != 0) {
                    fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Failed to re-import X25519 peer key with normalized MSB, rc=%d\n", rc);
                    fflush(stderr);
                    ok = 0;
                } else {
                    fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: X25519 peer key re-imported with normalized MSB successfully\n");
                    fflush(stderr);
                    /* Verify the re-import worked by exporting again */
                    word32 verify_len = CURVE25519_KEYSIZE;
                    byte verify_pub[CURVE25519_KEYSIZE];
                    rc = wc_curve25519_export_public_ex((curve25519_key*)peer_key, verify_pub, &verify_len, EC25519_LITTLE_ENDIAN);
                    if (rc == 0 && verify_len == CURVE25519_KEYSIZE) {
                        fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Verification export - last byte=0x%02x (MSB=%d)\n",
                                verify_pub[CURVE25519_KEYSIZE - 1], (verify_pub[CURVE25519_KEYSIZE - 1] & 0x80) ? 1 : 0);
                        fflush(stderr);
                    }
                }
            } else {
                fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Not X25519 (export failed or wrong size), skipping MSB fix\n");
                fflush(stderr);
            }
            /* If export failed or size != 32, it's X448 or another type - skip MSB fix */
            /* X448 doesn't require MSB clearing per RFC 7748 */
        } else {
            fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: peer_key is NULL, skipping MSB fix\n");
            fflush(stderr);
        }
    }
#endif /* WP_HAVE_X25519 */
    fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: MSB fix complete, ok=%d\n", ok);
    fflush(stderr);
    
    if (ok) {
        ctx->peer = peer;
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Peer set successfully\n");
        fflush(stderr);
    }

    WOLFPROV_LEAVE(WP_LOG_COMP_X25519, __FILE__ ":" WOLFPROV_STRINGIZE(__LINE__), ok);
    return ok;
}

#ifdef WP_HAVE_X25519

/*
 * X25519
 */

/** Order of Curve25519. Subtract from secret if larger. */
const unsigned char wp_curve25519_order[] = {
    0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xed
};

/**
 * Derive a secret/key using X25519.
 *
 * Can put the secret through a KDF.
 *
 * @param [in]  ctx      ECX key exchange context object.
 * @param [out] secret   Buffer to hold secret/key.
 * @param [out] secLen   Length of secret/key data in bytes.
 * @param [in]  secSize  Size of buffer in bytes.
 * @return 1 on success.
 * @return 0 on failure.
 */
static int wp_x25519_derive(wp_EcxCtx* ctx, unsigned char* secret,
    size_t* secLen, size_t secSize)
{
    int ok = 1;

    WOLFPROV_ENTER(WP_LOG_COMP_X25519, "wp_x25519_derive");

    /* UNCONDITIONAL DEBUG: Always print to stderr regardless of debug build */
    fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ENTER ctx=%p, secret=%p, secLen=%p, secSize=%zu\n",
            ctx, secret, secLen, secSize);
    fflush(stderr);
    
    if (ctx != NULL) {
        fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ctx->key=%p, ctx->peer=%p\n",
                ctx->key, ctx->peer);
        fflush(stderr);
    }

    if (!wolfssl_prov_is_running()) {
        fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Provider not running!\n");
        fflush(stderr);
        ok = 0;
    }

    /* Validate context and keys before use */
    if (ok && ctx == NULL) {
        fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ctx is NULL!\n");
        fflush(stderr);
        ok = 0;
    }
    if (ok && ctx->key == NULL) {
        fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ctx->key is NULL!\n");
        fflush(stderr);
        ok = 0;
    }
    if (ok && ctx->peer == NULL) {
        fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ctx->peer is NULL!\n");
        fflush(stderr);
        ok = 0;
    }

    /* No output buffer, return secret size only. */
    if (ok && (secret == NULL)) {
        *secLen = CURVE25519_KEYSIZE;
        fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Returning secret size only: %d\n", CURVE25519_KEYSIZE);
        fflush(stderr);
    }
    else if (ok) {
        int rc;
        word32 len = (word32)secSize;
        int i;
        
        void* key_ptr = NULL;
        void* peer_ptr = NULL;
        
        /* Get key pointers with validation */
        if (ctx->key != NULL) {
            key_ptr = wp_ecx_get_key(ctx->key);
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Got key_ptr=%p from ctx->key\n", key_ptr);
            fflush(stderr);
            if (key_ptr == NULL) {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: wp_ecx_get_key(ctx->key) returned NULL!\n");
                fflush(stderr);
                ok = 0;
            }
        } else {
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ctx->key is NULL before wp_ecx_get_key!\n");
            fflush(stderr);
            ok = 0;
        }
        
        if (ok && ctx->peer != NULL) {
            peer_ptr = wp_ecx_get_key(ctx->peer);
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Got peer_ptr=%p from ctx->peer\n", peer_ptr);
            fflush(stderr);
            if (peer_ptr == NULL) {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: wp_ecx_get_key(ctx->peer) returned NULL!\n");
                fflush(stderr);
                ok = 0;
            }
        } else if (ok) {
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ctx->peer is NULL before wp_ecx_get_key!\n");
            fflush(stderr);
            ok = 0;
        }

        if (ok) {
            /* Call wc_curve25519_shared_secret directly */
            /* Keys should already be normalized in wp_ecx_set_peer for peer key */
            /* Local key should be fine as-is since it was created/generated properly */
            curve25519_key* local_key = (curve25519_key*)key_ptr;
            curve25519_key* peer_key_derive = (curve25519_key*)peer_ptr;
            
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ===== KEY STATE BEFORE OPERATION =====\n");
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: local_key=%p, peer_key_derive=%p\n", 
                    local_key, peer_key_derive);
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Memory alignment - local_key alignment=%zu, peer_key alignment=%zu\n",
                    (size_t)local_key % 8, (size_t)peer_key_derive % 8);
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ctx->key=%p, ctx->peer=%p\n",
                    ctx->key, ctx->peer);
            fflush(stderr);
            
            /* Export and check both keys in detail */
            byte local_pub[CURVE25519_KEYSIZE];
            byte peer_pub[CURVE25519_KEYSIZE];
            byte local_priv[CURVE25519_KEYSIZE];
            word32 local_pub_len = CURVE25519_KEYSIZE;
            word32 peer_pub_len = CURVE25519_KEYSIZE;
            word32 local_priv_len = CURVE25519_KEYSIZE;
            
            int rc_local_pub = wc_curve25519_export_public_ex(local_key, local_pub, &local_pub_len, EC25519_LITTLE_ENDIAN);
            int rc_peer_pub = wc_curve25519_export_public_ex(peer_key_derive, peer_pub, &peer_pub_len, EC25519_LITTLE_ENDIAN);
            int rc_local_priv = wc_curve25519_export_private_raw_ex(local_key, local_priv, &local_priv_len, EC25519_LITTLE_ENDIAN);
            
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: LOCAL key export - pub: rc=%d, len=%u, last_byte=0x%02x (MSB=%s)\n",
                    rc_local_pub, local_pub_len, 
                    (local_pub_len == CURVE25519_KEYSIZE) ? local_pub[CURVE25519_KEYSIZE - 1] : 0,
                    (local_pub_len == CURVE25519_KEYSIZE && (local_pub[CURVE25519_KEYSIZE - 1] & 0x80)) ? "SET" : "CLEAR");
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: LOCAL key export - priv: rc=%d, len=%u", rc_local_priv, local_priv_len);
            if (rc_local_priv == 0 && local_priv_len == CURVE25519_KEYSIZE) {
                /* Check private key clamping: bits 0,1,2 should be 0, bit 254 should be 0, bit 255 should be 0 */
                int bit0 = (local_priv[0] & 0x07);
                int bit254 = (local_priv[31] & 0x40) >> 6;
                int bit255 = (local_priv[31] & 0x80) >> 7;
                fprintf(stderr, ", first_byte=0x%02x (bits 0-2=%d), last_byte=0x%02x (bit254=%d, bit255=%d)", 
                        local_priv[0], bit0, local_priv[31], bit254, bit255);
                if (bit0 != 0 || bit254 != 0 || bit255 != 0) {
                    fprintf(stderr, " [NOT PROPERLY CLAMPED!]");
                } else {
                    fprintf(stderr, " [PROPERLY CLAMPED]");
                }
            }
            fprintf(stderr, "\n");
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: PEER key export - pub: rc=%d, len=%u, last_byte=0x%02x (MSB=%s)\n",
                    rc_peer_pub, peer_pub_len,
                    (peer_pub_len == CURVE25519_KEYSIZE) ? peer_pub[CURVE25519_KEYSIZE - 1] : 0,
                    (peer_pub_len == CURVE25519_KEYSIZE && (peer_pub[CURVE25519_KEYSIZE - 1] & 0x80)) ? "SET" : "CLEAR");
            fflush(stderr);
            
            /* Check keys before calling - export public keys first, then check */
            int check_local = -1;
            int check_peer = -1;
            if (rc_local_pub == 0 && local_pub_len == CURVE25519_KEYSIZE) {
                check_local = wc_curve25519_check_public(local_pub, CURVE25519_KEYSIZE, EC25519_LITTLE_ENDIAN);
            }
            if (rc_peer_pub == 0 && peer_pub_len == CURVE25519_KEYSIZE) {
                check_peer = wc_curve25519_check_public(peer_pub, CURVE25519_KEYSIZE, EC25519_LITTLE_ENDIAN);
            }
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Key validation checks - local=%d, peer=%d (0=valid)\n", 
                    check_local, check_peer);
            fflush(stderr);
            
            /* CRITICAL: Check if local key has private key before calling shared_secret */
            /* wc_curve25519_shared_secret requires local key to have a private key */
            if (rc_local_priv != 0 || local_priv_len != CURVE25519_KEYSIZE) {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ERROR - Local key private key export failed! rc=%d, len=%u\n",
                        rc_local_priv, local_priv_len);
                fflush(stderr);
                ok = 0;
            }
            
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ===== PRE-CALL VALIDATION =====\n");
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Validating keys before wc_curve25519_shared_secret call...\n");
            fflush(stderr);
            
            /* Additional validation: Try to check public keys directly from key structures */
            int check_local_direct = -999;
            int check_peer_direct = -999;
            if (rc_local_pub == 0 && local_pub_len == CURVE25519_KEYSIZE) {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [PRE-CALL] Calling wc_curve25519_check_public on LOCAL exported bytes...\n");
                fflush(stderr);
                check_local_direct = wc_curve25519_check_public(local_pub, local_pub_len, EC25519_LITTLE_ENDIAN);
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [PRE-CALL] wc_curve25519_check_public(LOCAL) returned %d (0=valid)\n", check_local_direct);
                fflush(stderr);
            }
            if (rc_peer_pub == 0 && peer_pub_len == CURVE25519_KEYSIZE) {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [PRE-CALL] Calling wc_curve25519_check_public on PEER exported bytes...\n");
                fflush(stderr);
                check_peer_direct = wc_curve25519_check_public(peer_pub, peer_pub_len, EC25519_LITTLE_ENDIAN);
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [PRE-CALL] wc_curve25519_check_public(PEER) returned %d (0=valid)\n", check_peer_direct);
                fflush(stderr);
            }
            
            /* Check if we can re-export immediately before the call */
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [PRE-CALL] Re-exporting keys immediately before call...\n");
            fflush(stderr);
            word32 pre_call_local_pub_len = CURVE25519_KEYSIZE;
            word32 pre_call_peer_pub_len = CURVE25519_KEYSIZE;
            byte pre_call_local_pub[CURVE25519_KEYSIZE];
            byte pre_call_peer_pub[CURVE25519_KEYSIZE];
            int pre_call_local_rc = wc_curve25519_export_public_ex(local_key, pre_call_local_pub, &pre_call_local_pub_len, EC25519_LITTLE_ENDIAN);
            int pre_call_peer_rc = wc_curve25519_export_public_ex(peer_key_derive, pre_call_peer_pub, &pre_call_peer_pub_len, EC25519_LITTLE_ENDIAN);
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [PRE-CALL] Re-export results - local: rc=%d, len=%u, last_byte=0x%02x (MSB=%s)\n",
                    pre_call_local_rc, pre_call_local_pub_len,
                    (pre_call_local_pub_len == CURVE25519_KEYSIZE) ? pre_call_local_pub[CURVE25519_KEYSIZE - 1] : 0,
                    (pre_call_local_pub_len == CURVE25519_KEYSIZE && (pre_call_local_pub[CURVE25519_KEYSIZE - 1] & 0x80)) ? "SET" : "CLEAR");
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [PRE-CALL] Re-export results - peer: rc=%d, len=%u, last_byte=0x%02x (MSB=%s)\n",
                    pre_call_peer_rc, pre_call_peer_pub_len,
                    (pre_call_peer_pub_len == CURVE25519_KEYSIZE) ? pre_call_peer_pub[CURVE25519_KEYSIZE - 1] : 0,
                    (pre_call_peer_pub_len == CURVE25519_KEYSIZE && (pre_call_peer_pub[CURVE25519_KEYSIZE - 1] & 0x80)) ? "SET" : "CLEAR");
            fflush(stderr);
            
            /* Validate the pre-call exported keys */
            if (pre_call_local_rc == 0 && pre_call_peer_rc == 0) {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [PRE-CALL] Validating pre-call exported keys...\n");
                fflush(stderr);
                int pre_check_local = wc_curve25519_check_public(pre_call_local_pub, pre_call_local_pub_len, EC25519_LITTLE_ENDIAN);
                int pre_check_peer = wc_curve25519_check_public(pre_call_peer_pub, pre_call_peer_pub_len, EC25519_LITTLE_ENDIAN);
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [PRE-CALL] Pre-call validation - local=%d, peer=%d (0=valid)\n", 
                        pre_check_local, pre_check_peer);
                fflush(stderr);
            }
            
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ===== CALLING wc_curve25519_shared_secret =====\n");
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [BEFORE] Function call: wc_curve25519_shared_secret(local_key=%p, peer_key=%p, secret=%p, len=%p)\n",
                    local_key, peer_key_derive, secret, &len);
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [BEFORE] Local key has private: %s (export rc=%d)\n",
                    (rc_local_priv == 0 && local_priv_len == CURVE25519_KEYSIZE) ? "YES" : "NO", rc_local_priv);
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [BEFORE] Secret buffer: %p, len pointer: %p, current len value: %u\n",
                    secret, &len, len);
            fflush(stderr);
            
            if (ok) {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [CALL] Executing wc_curve25519_shared_secret...\n");
                fflush(stderr);
                rc = wc_curve25519_shared_secret(local_key, peer_key_derive, secret, &len);
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [AFTER] wc_curve25519_shared_secret returned: rc=%d\n", rc);
                fflush(stderr);
            } else {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [SKIP] Not calling wc_curve25519_shared_secret (ok=0, missing private key)\n");
                fflush(stderr);
                rc = -199; /* Set error if we detected missing private key */
            }
            
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ===== RESULT FROM wc_curve25519_shared_secret =====\n");
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [RESULT] Return code: %d (0=success, -199=ECC_BAD_ARG_E)\n", rc);
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [RESULT] Output length: %u\n", len);
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [RESULT] Secret buffer after call: %p\n", secret);
            if (rc == 0 && secret != NULL) {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [RESULT] First 4 bytes of secret: 0x%02x 0x%02x 0x%02x 0x%02x\n",
                        secret[0], secret[1], secret[2], secret[3]);
            }
            fflush(stderr);
            
            if (rc != 0) {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ===== FAILURE ANALYSIS =====\n");
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [FAIL] Error code %d (ECC_BAD_ARG_E=-199 means MSB check failed or invalid key)\n", rc);
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [FAIL] Re-checking keys after failure...\n");
                fflush(stderr);
                
                /* Re-export to see if anything changed */
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [POST-FAIL] Re-exporting LOCAL key...\n");
                fflush(stderr);
                word32 local_pub_len2 = CURVE25519_KEYSIZE;
                word32 local_priv_len2 = CURVE25519_KEYSIZE;
                byte local_pub2[CURVE25519_KEYSIZE];
                byte local_priv2[CURVE25519_KEYSIZE];
                int rc_local2_pub = wc_curve25519_export_public_ex(local_key, local_pub2, &local_pub_len2, EC25519_LITTLE_ENDIAN);
                int rc_local2_priv = wc_curve25519_export_private_raw_ex(local_key, local_priv2, &local_priv_len2, EC25519_LITTLE_ENDIAN);
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [POST-FAIL] LOCAL re-export - pub: rc=%d, len=%u, last_byte=0x%02x (MSB=%s)\n",
                        rc_local2_pub, local_pub_len2,
                        (local_pub_len2 == CURVE25519_KEYSIZE) ? local_pub2[CURVE25519_KEYSIZE - 1] : 0,
                        (local_pub_len2 == CURVE25519_KEYSIZE && (local_pub2[CURVE25519_KEYSIZE - 1] & 0x80)) ? "SET" : "CLEAR");
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [POST-FAIL] LOCAL re-export - priv: rc=%d, len=%u\n",
                        rc_local2_priv, local_priv_len2);
                if (rc_local2_pub == 0 && local_pub_len2 == CURVE25519_KEYSIZE) {
                    int check_local_post = wc_curve25519_check_public(local_pub2, local_pub_len2, EC25519_LITTLE_ENDIAN);
                    fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [POST-FAIL] LOCAL validation check: %d (0=valid)\n", check_local_post);
                }
                fflush(stderr);
                
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [POST-FAIL] Re-exporting PEER key...\n");
                fflush(stderr);
                word32 peer_pub_len2 = CURVE25519_KEYSIZE;
                byte peer_pub2[CURVE25519_KEYSIZE];
                int rc_peer2 = wc_curve25519_export_public_ex(peer_key_derive, peer_pub2, &peer_pub_len2, EC25519_LITTLE_ENDIAN);
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [POST-FAIL] PEER re-export - pub: rc=%d, len=%u, last_byte=0x%02x (MSB=%s)\n",
                        rc_peer2, peer_pub_len2,
                        (peer_pub_len2 == CURVE25519_KEYSIZE) ? peer_pub2[CURVE25519_KEYSIZE - 1] : 0,
                        (peer_pub_len2 == CURVE25519_KEYSIZE && (peer_pub2[CURVE25519_KEYSIZE - 1] & 0x80)) ? "SET" : "CLEAR");
                if (rc_peer2 == 0 && peer_pub_len2 == CURVE25519_KEYSIZE) {
                    int check_peer_post = wc_curve25519_check_public(peer_pub2, peer_pub_len2, EC25519_LITTLE_ENDIAN);
                    fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [POST-FAIL] PEER validation check: %d (0=valid)\n", check_peer_post);
                }
                fflush(stderr);
                
                /* Compare pre-call and post-fail exports */
                if (pre_call_local_rc == 0 && rc_local2_pub == 0 && 
                    pre_call_peer_rc == 0 && rc_peer2 == 0) {
                    fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [POST-FAIL] Comparing pre-call vs post-fail exports...\n");
                    int local_changed = 0;
                    int peer_changed = 0;
                    int j;
                    for (j = 0; j < CURVE25519_KEYSIZE; j++) {
                        if (pre_call_local_pub[j] != local_pub2[j]) {
                            local_changed = 1;
                            break;
                        }
                    }
                    for (j = 0; j < CURVE25519_KEYSIZE; j++) {
                        if (pre_call_peer_pub[j] != peer_pub2[j]) {
                            peer_changed = 1;
                            break;
                        }
                    }
                    fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [POST-FAIL] Key changes - local: %s, peer: %s\n",
                            local_changed ? "CHANGED" : "UNCHANGED",
                            peer_changed ? "CHANGED" : "UNCHANGED");
                    fflush(stderr);
                }
                
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: ===== END FAILURE ANALYSIS =====\n");
                fflush(stderr);
                ok = 0;
            } else {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [SUCCESS] Shared secret derived successfully, len=%u\n", len);
                if (secret != NULL && len > 0) {
                    fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: [SUCCESS] Secret bytes (first 8): ");
                    size_t print_len = (len < 8) ? len : 8;
                    size_t k;
                    for (k = 0; k < print_len; k++) {
                        fprintf(stderr, "0x%02x ", secret[k]);
                    }
                    fprintf(stderr, "\n");
                }
                fflush(stderr);
            }
        }
        if (ok) {
            for (i = 0; i < CURVE25519_KEYSIZE; i++) {
                if (secret[i] != wp_curve25519_order[i]) {
                    break;
                }
            }
            if ((i < CURVE25519_KEYSIZE) &&
                (secret[i] > wp_curve25519_order[i])) {
                int16_t carry = 0;
                for (i = CURVE25519_KEYSIZE - 1; i >= 0; i--) {
                    carry += secret[i];
                    carry -= wp_curve25519_order[i];
                    secret[i] = (unsigned char)carry;
                    carry >>= 8;
                }
            }
        }
        if (ok) {
            *secLen = len;
            /* Switch endian. */
            for (i = 0; i < (int)len / 2; i++) {
                byte t = secret[i];
                secret[i] = secret[len - 1 - i];
                secret[len - 1 - i] = t;
            }
        }
    }

    fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: EXIT returning %d\n", ok);
    fflush(stderr);
    WOLFPROV_LEAVE(WP_LOG_COMP_X25519, __FILE__ ":" WOLFPROV_STRINGIZE(__LINE__), ok);
    return ok;
}

/** Dispatch table for X25519 key exchange. */
const OSSL_DISPATCH wp_x25519_keyexch_functions[] = {
    { OSSL_FUNC_KEYEXCH_NEWCTX,    (DFUNC)wp_ecx_newctx    },
    { OSSL_FUNC_KEYEXCH_FREECTX,   (DFUNC)wp_ecx_freectx   },
    { OSSL_FUNC_KEYEXCH_DUPCTX,    (DFUNC)wp_ecx_dupctx    },
    { OSSL_FUNC_KEYEXCH_INIT,      (DFUNC)wp_ecx_init      },
    { OSSL_FUNC_KEYEXCH_DERIVE,    (DFUNC)wp_x25519_derive },
    { OSSL_FUNC_KEYEXCH_SET_PEER,  (DFUNC)wp_ecx_set_peer  },
    { 0, NULL }
};

#endif /* WP_HAVE_X25519 */

#ifdef WP_HAVE_X448

/*
 * X448
 */

/**
 * Derive a secret/key using X448.
 *
 * Can put the secret through a KDF.
 *
 * @param [in]  ctx      ECX key exchange context object.
 * @param [out] secret   Buffer to hold secret/key.
 * @param [out] secLen   Length of secret/key data in bytes.
 * @param [in]  secSize  Size of buffer in bytes.
 * @return 1 on success.
 * @return 0 on failure.
 */
static int wp_x448_derive(wp_EcxCtx* ctx, unsigned char* secret,
    size_t* secLen, size_t secSize)
{
    int ok = 1;

    WOLFPROV_ENTER(WP_LOG_COMP_X448, "wp_x448_derive");

    if (!wolfssl_prov_is_running()) {
        ok = 0;
    }

    /* No output buffer, return secret size only. */
    if (ok && (secret == NULL)) {
        *secLen = CURVE448_KEY_SIZE;
    }
    else if (ok) {
        int rc;
        word32 len = (word32)secSize;

        rc = wc_curve448_shared_secret(wp_ecx_get_key(ctx->key),
            wp_ecx_get_key(ctx->peer), secret, &len);
        if (rc != 0) {
            WOLFPROV_MSG_DEBUG_RETCODE(WP_LOG_LEVEL_DEBUG, "wc_curve448_shared_secret", rc);
            ok = 0;
        }
        if (ok) {
            word32 i;

            *secLen = len;
            /* Switch endian. */
            for (i = 0; i < len / 2; i++) {
                byte t = secret[i];
                secret[i] = secret[len - 1 - i];
                secret[len - 1 - i] = t;
            }
        }
    }

    WOLFPROV_LEAVE(WP_LOG_COMP_X448, __FILE__ ":" WOLFPROV_STRINGIZE(__LINE__), ok);
    return ok;
}

/** Dispatch table for X448 key exchange. */
const OSSL_DISPATCH wp_x448_keyexch_functions[] = {
    { OSSL_FUNC_KEYEXCH_NEWCTX,    (DFUNC)wp_ecx_newctx   },
    { OSSL_FUNC_KEYEXCH_FREECTX,   (DFUNC)wp_ecx_freectx  },
    { OSSL_FUNC_KEYEXCH_DUPCTX,    (DFUNC)wp_ecx_dupctx   },
    { OSSL_FUNC_KEYEXCH_INIT,      (DFUNC)wp_ecx_init     },
    { OSSL_FUNC_KEYEXCH_DERIVE,    (DFUNC)wp_x448_derive  },
    { OSSL_FUNC_KEYEXCH_SET_PEER,  (DFUNC)wp_ecx_set_peer },
    { 0, NULL }
};

#endif /* WP_HAVE_X448 */

#endif /* WP_HAVE_X25519 || WP_HAVE_X448 */

