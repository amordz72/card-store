// Fingerprint / face unlock through the browser (WebAuthn, device authenticator).
// The biometric check happens on the device; nothing biometric is sent or stored by the app.

const rnd = (n) => crypto.getRandomValues(new Uint8Array(n))
const toB64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)))
const fromB64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0))

export async function bioAvailable () {
  try {
    return !!window.PublicKeyCredential && await window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()
  } catch {
    return false
  }
}

// Returns the credential id to remember on this device
export async function bioRegister (label) {
  const cred = await navigator.credentials.create({
    publicKey: {
      challenge: rnd(32),
      rp: { name: 'متجر البطاقات' },
      user: { id: rnd(16), name: label, displayName: label },
      pubKeyCredParams: [{ type: 'public-key', alg: -7 }, { type: 'public-key', alg: -257 }],
      authenticatorSelection: { authenticatorAttachment: 'platform', userVerification: 'required', residentKey: 'discouraged' },
      attestation: 'none',
      timeout: 60000
    }
  })
  return toB64(cred.rawId)
}

// true only when the device confirmed the user (fingerprint, face or device screen lock)
export async function bioVerify (credentialId) {
  const a = await navigator.credentials.get({
    publicKey: {
      challenge: rnd(32),
      allowCredentials: [{ type: 'public-key', id: fromB64(credentialId), transports: ['internal'] }],
      userVerification: 'required',
      timeout: 60000
    }
  })
  const flags = new Uint8Array(a.response.authenticatorData)[32]
  return (flags & 0x04) !== 0   // UV flag
}
