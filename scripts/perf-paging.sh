#!/bin/zsh
# scripts/perf-paging.sh <label> [testPagingHitches|testSalahVerticalHitches] — Release swipe test on his 13 Pro Max
# (scheme shukrPerf; the phone unlocked, Settings → Developer → Enable UI Automation on). Prints hitches per run;
# Apple: < 5 ms/s smooth, > 10 ms/s visible. PERF_ARGS="-x -y" adds launch args. Results: build/perf-results/.
cd "/Users/izhanansari/Coding and Tinkering/shukrGit/shukr"
L=$1; T=${2:-testPagingHitches}
K="$HOME/.appstoreconnect/private_keys/AuthKey_6K2RUXRJ92.p8"
mkdir -p build/perf-results; R=build/perf-results/dev-$L-$(date +%H%M%S).xcresult
TEST_RUNNER_PERF_ARGS="$PERF_ARGS" xcodebuild test -project shukr.xcodeproj -scheme shukrPerf -destination 'id=00008110-001C041C2203801E' -derivedDataPath build/perf-dev -allowProvisioningUpdates -authenticationKeyPath "$K" -authenticationKeyID 6K2RUXRJ92 -authenticationKeyIssuerID 60a885ac-0315-4323-974d-57783a7392a2 SHUKR_BUILD_STAMP="$(git rev-parse --short HEAD)+perf" -only-testing:shukrUITests/shukrUITests/$T -resultBundlePath $R > build/perf-results/dev-$L.log 2>&1
grep -E "Test Case.*(passed|failed)|encountered an error|\*\* TEST" build/perf-results/dev-$L.log | cut -c1-200
python3 - $R <<'PY'
import json,subprocess,sys
R=sys.argv[1]
def get(id=None):
    cmd=["xcrun","xcresulttool","get","object","--legacy","--path",R,"--format","json"]+(["--id",id] if id else [])
    return json.loads(subprocess.check_output(cmd))
def find(o,key):
    if isinstance(o,dict):
        if key in o: yield o
        for v in o.values(): yield from find(v,key)
    elif isinstance(o,list):
        for v in o: yield from find(v,key)
try:
    root=get(); ref=root["actions"]["_values"][0]["actionResult"]["testsRef"]["id"]["_value"]
    for s in find(get(ref),"summaryRef"):
        for pm in find(get(s["summaryRef"]["id"]["_value"]),"performanceMetrics"):
            for m in pm["performanceMetrics"].get("_values",[]):
                vals=[round(float(v["_value"]),1) for v in m["measurements"]["_values"]]
                print(f'{m["displayName"]["_value"]:55} {m.get("unitOfMeasurement",{}).get("_value",""):8} {vals}')
except Exception as e: print("no metrics:",e)
PY
