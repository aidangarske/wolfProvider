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
    fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: ctx=%p, ecx=%p\n", ctx, ecx);
    fflush(stderr);

    /* No settable parameters. */
    (void)params;

    if (!wolfssl_prov_is_running()) {
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: Provider not running!\n");
        fflush(stderr);
        ok = 0;
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
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_init: Key set successfully\n");
        fflush(stderr);
    }

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
    fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: ctx=%p, peer=%p\n", ctx, peer);
    fflush(stderr);

    if (!wolfssl_prov_is_running()) {
        fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Provider not running!\n");
        fflush(stderr);
        ok = 0;
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
    /* 4. We re-import using peer->data->importPub (wp_x25519_import_public) which handles MSB clearing */
    if (ok && peer != NULL && peer->data != NULL && peer->data->importPub != NULL) {
        curve25519_key* peer_key = (curve25519_key*)wp_ecx_get_key(peer);
        if (peer_key != NULL) {
            byte peer_pub[CURVE25519_KEYSIZE];
            word32 peer_pub_len = CURVE25519_KEYSIZE;
            int rc;
            
            /* Export peer public key to get raw bytes */
            rc = wc_curve25519_export_public_ex(peer_key, peer_pub, &peer_pub_len, EC25519_LITTLE_ENDIAN);
            if (rc == 0 && peer_pub_len == CURVE25519_KEYSIZE) {
                /* Check if MSB (bit 7 of last byte) is set - RFC 7748 requires it to be clear */
                if ((peer_pub[CURVE25519_KEYSIZE - 1] & 0x80) != 0x00) {
                    fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Peer key MSB is set, re-importing with MSB cleared (RFC 7748)\n");
                    fflush(stderr);
                    /* Re-import using wp_x25519_import_public (via peer->data->importPub) */
                    /* This function automatically clears MSB if set - matching OpenSSL's behavior */
                    /* We pass the exported bytes (which may have MSB set) and let importPub handle clearing */
                    rc = (*peer->data->importPub)(peer_pub, CURVE25519_KEYSIZE, peer_key, EC25519_LITTLE_ENDIAN);
                    if (rc != 0) {
                        fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Failed to re-import peer key with MSB cleared, rc=%d\n", rc);
                        fflush(stderr);
                        ok = 0;
                    } else {
                        fprintf(stderr, "[X25519-DEBUG] wp_ecx_set_peer: Peer key re-imported with MSB cleared successfully\n");
                        fflush(stderr);
                    }
                }
            }
        }
    }
    
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
            /* Note: MSB clearing is now done in wp_ecx_set_peer() when peer is set */
            /* This ensures RFC 7748 compliance once, not on every derive call */
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: Calling wc_curve25519_shared_secret with key_ptr=%p, peer_ptr=%p\n", 
                    key_ptr, peer_ptr);
            fflush(stderr);
            rc = wc_curve25519_shared_secret((curve25519_key*)key_ptr, (curve25519_key*)peer_ptr, secret, &len);
            fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: wc_curve25519_shared_secret returned %d, len=%u\n", rc, len);
            fflush(stderr);
            
            if (rc != 0) {
                fprintf(stderr, "[X25519-DEBUG] wp_x25519_derive: wc_curve25519_shared_secret FAILED with rc=%d\n", rc);
                fflush(stderr);
                ok = 0;
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

