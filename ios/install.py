#!/usr/bin/env python3
"""Build, provision, install, and launch after the account holder accepts Apple's PLA."""
from pathlib import Path
import argparse
import hashlib
import datetime
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

arguments=argparse.ArgumentParser()
arguments.add_argument("--no-launch",action="store_true",help="Install without opening the app or claiming Bluetooth")
args=arguments.parse_args()

ROOT=Path(__file__).resolve().parent
TEAM=(ROOT/".development-team").read_text().strip()
UDID=(ROOT/".device-udid").read_text().strip()
DEVICE=(ROOT/".device-id").read_text().strip()
LOG=ROOT/"device-build.log"
APP=ROOT/"build/Build/Products/Release-iphoneos/S1Pocket.app"

# Prefer a valid existing wildcard development profile when Xcode's automatic
# profile cache references a profile that was never downloaded.
identity_text=subprocess.run(["security","find-identity","-v","-p","codesigning"],capture_output=True,text=True,check=True).stdout
identities=set(re.findall(r'\) ([A-Fa-f0-9]{40}) "',identity_text))
profile_id=None
profile_path=None
profile_entitlements=None
identity=None
for path in (Path.home()/"Library/Developer/Xcode/UserData/Provisioning Profiles").glob("*.mobileprovision"):
    decoded=subprocess.run(["security","cms","-D","-i",str(path)],capture_output=True)
    if decoded.returncode:continue
    profile=plistlib.loads(decoded.stdout)
    entitlements=profile.get("Entitlements",{})
    certificate_hashes={hashlib.sha1(c).hexdigest().upper() for c in profile.get("DeveloperCertificates",[])}
    if (entitlements.get("application-identifier")==TEAM+".*"
        and entitlements.get("get-task-allow")
        and UDID in profile.get("ProvisionedDevices",[])
        and profile.get("ExpirationDate",datetime.datetime.min)>datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
        and identities & certificate_hashes):
        profile_id=profile["UUID"]
        profile_path=path
        profile_entitlements=entitlements
        identity=sorted(identities & certificate_hashes)[0]
        break
# Build without Xcode's cached signing plan when a suitable Apple-issued
# profile is already available. Sign the resulting code with that same valid
# development certificate and profile using Apple's codesign tool.
signing=["CODE_SIGNING_ALLOWED=NO"] if profile_id else []

with LOG.open("w") as stream:
    build=subprocess.run([
        "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild",
        "-project",str(ROOT.parent/"S1Sticker.xcodeproj"),"-scheme","S1Pocket",
        "-configuration","Release","-derivedDataPath",str(ROOT/"build"),
        "-allowProvisioningUpdates","-allowProvisioningDeviceRegistration",
        "DEVELOPMENT_TEAM="+TEAM,"-destination","id="+UDID,*signing,"build"
    ],stdout=stream,stderr=subprocess.STDOUT,cwd=ROOT)
if build.returncode:
    for line in LOG.read_text().splitlines():
        if "error:" in line:print(line)
    raise SystemExit(build.returncode)

if profile_id:
    def expand(value,bundle):
        if isinstance(value,str):return value.replace(TEAM+".*",TEAM+"."+bundle)
        if isinstance(value,list):return [expand(v,bundle) for v in value]
        if isinstance(value,dict):return {k:expand(v,bundle) for k,v in value.items()}
        return value
    with tempfile.TemporaryDirectory(prefix="s1-sign-") as directory:
        for library in APP.rglob("*.dylib"):
            subprocess.run(["codesign","--force","--sign",identity,str(library)],check=True)
        for bundle_path in [*APP.glob("PlugIns/*.appex"),APP]:
            bundle_id=plistlib.loads((bundle_path/"Info.plist").read_bytes())["CFBundleIdentifier"]
            entitlements=expand(profile_entitlements,bundle_id)
            entitlements["application-identifier"]=TEAM+"."+bundle_id
            entitlements_path=Path(directory)/(bundle_path.name+".plist")
            entitlements_path.write_bytes(plistlib.dumps(entitlements))
            shutil.copyfile(profile_path,bundle_path/"embedded.mobileprovision")
            subprocess.run(["codesign","--force","--sign",identity,"--entitlements",str(entitlements_path),"--generate-entitlement-der",str(bundle_path)],check=True)
        subprocess.run(["codesign","--verify","--deep","--strict",str(APP)],check=True)

ctl="/Library/Developer/PrivateFrameworks/CoreDevice.framework/Versions/A/Resources/bin/devicectl"
subprocess.run([ctl,"device","install","app","--device",DEVICE,str(APP),"--timeout","60"],check=True)
if args.no_launch:
    print("Installed S1 Sticker. Open it on the iPhone when ready.")
    raise SystemExit(0)
launch=subprocess.run([ctl,"device","process","launch","--device",DEVICE,"--terminate-existing","local.chad.S1Pocket","--timeout","30"],capture_output=True,text=True)
if launch.returncode:
    if "Locked" in launch.stdout+launch.stderr or "could not be, unlocked" in launch.stdout+launch.stderr:
        print("Installed S1 Sticker. The iPhone is locked; unlock it and open S1 Sticker when ready.")
    else:
        print(launch.stdout+launch.stderr)
        raise SystemExit(launch.returncode)
else:
    print("Installed and launched S1 Sticker. Allow Bluetooth on the iPhone, then print a test sticker.")
