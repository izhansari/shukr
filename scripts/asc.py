#!/usr/bin/env python3
"""Tiny App Store Connect API client (stdlib + openssl), signed with the team API key.

    scripts/asc.py builds                      # recent builds: number, state, expiry
    scripts/asc.py groups                      # beta groups
    scripts/asc.py release 8 notes.txt         # build 8 → "What to Test" = notes.txt,
                                               #   add to every external group, submit for beta review
    scripts/asc.py GET /v1/apps                # raw call

The key file never leaves ~/.appstoreconnect/private_keys and is never printed.
"""
import base64, json, os, subprocess, sys, time, urllib.request, urllib.error

KEY_ID = "6K2RUXRJ92"
ISSUER_ID = "60a885ac-0315-4323-974d-57783a7392a2"
KEY_PATH = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8")
APP_ID = "6743040873"  # shukr
API = "https://api.appstoreconnect.apple.com"


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """ECDSA DER signature → the 64-byte r||s JWT wants."""
    assert der[0] == 0x30
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    out = b""
    for _ in range(2):
        assert der[i] == 0x02
        n = der[i + 1]
        v = der[i + 2 : i + 2 + n].lstrip(b"\x00")
        out += v.rjust(32, b"\x00")
        i += 2 + n
    return out


def token() -> str:
    header = b64(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}).encode())
    now = int(time.time())
    payload = b64(json.dumps({"iss": ISSUER_ID, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"}).encode())
    msg = f"{header}.{payload}".encode()
    der = subprocess.run(["/usr/bin/openssl", "dgst", "-sha256", "-sign", KEY_PATH],
                         input=msg, capture_output=True, check=True).stdout
    return f"{header}.{payload}.{b64(der_to_raw(der))}"


def call(method: str, path: str, body=None):
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        raise SystemExit(f"{method} {path} → {e.code}\n{detail}")


def builds():
    data = call("GET", f"/v1/builds?filter[app]={APP_ID}&sort=-uploadedDate&limit=8"
                       "&fields[builds]=version,processingState,expired,uploadedDate,usesNonExemptEncryption")
    for b in data["data"]:
        a = b["attributes"]
        print(f"{a['version']:>4}  {a['processingState']:<11} expired={a['expired']}  {a['uploadedDate'][:16]}  id={b['id']}")
    return data["data"]


def groups():
    data = call("GET", f"/v1/apps/{APP_ID}/betaGroups?fields[betaGroups]=name,isInternalGroup,publicLinkEnabled,publicLink")
    for g in data["data"]:
        a = g["attributes"]
        print(f"{a['name']:<10} internal={a['isInternalGroup']} publicLink={a.get('publicLink')} id={g['id']}")
    return data["data"]


def release(number: str, notes_path: str):
    notes = open(notes_path).read().strip()
    match = call("GET", f"/v1/builds?filter[app]={APP_ID}&filter[version]={number}&fields[builds]=version,processingState")["data"]
    if not match:
        raise SystemExit(f"No build {number} yet")
    build = match[0]
    state = build["attributes"]["processingState"]
    if state != "VALID":
        raise SystemExit(f"Build {number} is {state} — wait for Apple to finish processing")
    bid = build["id"]

    # What to Test (en-US)
    locs = call("GET", f"/v1/builds/{bid}/betaBuildLocalizations")["data"]
    en = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
    if en:
        call("PATCH", f"/v1/betaBuildLocalizations/{en['id']}",
             {"data": {"type": "betaBuildLocalizations", "id": en["id"], "attributes": {"whatsNew": notes}}})
    else:
        call("POST", "/v1/betaBuildLocalizations",
             {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": notes},
                       "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
    print("✓ What to Test set")

    # External groups (internal ones get builds automatically)
    for g in groups():
        if not g["attributes"]["isInternalGroup"]:
            call("POST", f"/v1/betaGroups/{g['id']}/relationships/builds", {"data": [{"type": "builds", "id": bid}]})
            print(f"✓ added to {g['attributes']['name']}")

    # Beta App Review (needed before external testers see it; skipped if already submitted/approved)
    try:
        call("POST", "/v1/betaAppReviewSubmissions",
             {"data": {"type": "betaAppReviewSubmissions",
                       "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
        print("✓ submitted for beta review")
    except SystemExit as e:
        print(f"beta review: {e}")
    detail = call("GET", f"/v1/builds/{bid}/buildBetaDetail")["data"]["attributes"]
    print(f"external state: {detail.get('externalBuildState')}  internal: {detail.get('internalBuildState')}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "builds"
    if cmd == "builds": builds()
    elif cmd == "groups": groups()
    elif cmd == "release": release(sys.argv[2], sys.argv[3])
    else: print(json.dumps(call(cmd, sys.argv[2], json.loads(sys.argv[3]) if len(sys.argv) > 3 else None), indent=1)[:4000])
