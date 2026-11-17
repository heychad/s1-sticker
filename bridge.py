#!/usr/bin/env python3
"""Private LAN printer bridge. No cloud, CORS, remote URLs, or shell execution."""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import tempfile
import threading
import urllib.parse

ROOT=Path(__file__).resolve().parent
STATE=Path.home()/"Library/Application Support/S1Sticker"
BINARY=Path.home()/"Applications/S1 Sticker.app/Contents/MacOS/S1Sticker"
VRETTI=Path.home()/"Applications/Vretti Print.app/Contents/MacOS/VrettiPrint"
STATE.mkdir(parents=True,exist_ok=True)
CONFIG=STATE/"bridge.json"
if CONFIG.exists():
    config=json.loads(CONFIG.read_text())
else:
    config={"token":secrets.token_urlsafe(32),"port":5112}
    fd=os.open(CONFIG,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,"w") as f: json.dump(config,f)

def addresses():
    local=[]
    for interface in ["en0","en1"]:
        p=subprocess.run(["/usr/sbin/ipconfig","getifaddr",interface],capture_output=True,text=True)
        value=p.stdout.strip()
        if p.returncode==0 and value and not value.startswith("169.254."):
            local.append(value)
    return list(dict.fromkeys(["127.0.0.1"]+local))

JOB_LOCK=threading.Lock()
JOBS=STATE/"bridge-jobs.json"
try: jobs=json.loads(JOBS.read_text())
except (FileNotFoundError,ValueError): jobs={}

def save_jobs():
    while len(jobs)>100: jobs.pop(next(iter(jobs)))
    tmp=JOBS.with_suffix(".tmp")
    fd=os.open(tmp,os.O_CREAT|os.O_TRUNC|os.O_WRONLY,0o600)
    with os.fdopen(fd,"w") as f: json.dump(jobs,f)
    os.replace(tmp,JOBS)

class Handler(BaseHTTPRequestHandler):
    server_version="S1Bridge"
    def log_message(self,*args): pass  # Never log tokens, content, or filenames.
    def send(self,status,body,kind="application/json"):
        if not isinstance(body,bytes): body=json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type",kind)
        self.send_header("Content-Length",str(len(body)))
        self.send_header("Cache-Control","no-store")
        self.send_header("X-Content-Type-Options","nosniff")
        self.send_header("Referrer-Policy","no-referrer")
        self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError,ConnectionResetError): pass
    def authorized(self):
        supplied=self.headers.get("Authorization","")
        return secrets.compare_digest(supplied,"Bearer "+config["token"])
    def do_GET(self):
        route=urllib.parse.urlsplit(self.path).path
        if route=="/": return self.send(200,(ROOT/"phone.html").read_bytes(),"text/html; charset=utf-8")
        if route=="/health": return self.send(200,{"ok":True,"service":"S1 Sticker"})
        if route!="/status": return self.send(404,{"ok":False})
        if not self.authorized(): return self.send(401,{"ok":False,"message":"Open the pairing link from your Mac first."})
        if not JOB_LOCK.acquire(blocking=False): return self.send(200,{"ok":True,"message":"A sticker is printing"})
        try:
            p=subprocess.run([str(BINARY),"--status"],capture_output=True,text=True,timeout=20)
            self.send(200,json.loads(p.stdout))
        except (ValueError,subprocess.TimeoutExpired): self.send(503,{"ok":False,"message":"Printer did not respond."})
        finally: JOB_LOCK.release()
    def do_POST(self):
        route=urllib.parse.urlsplit(self.path)
        if route.path not in ["/print","/print-text"]: return self.send(404,{"ok":False})
        if not self.authorized(): return self.send(401,{"ok":False,"message":"Pair this browser using the link from your Mac."})
        origin=self.headers.get("Origin")
        if origin and origin!="http://"+self.headers.get("Host",""):
            return self.send(403,{"ok":False,"message":"Cross-site requests are not allowed."})
        try: length=int(self.headers.get("Content-Length","0"))
        except ValueError: length=0
        if not 0<length<=20*1024*1024: return self.send(413,{"ok":False,"message":"Choose a file under 20 MB."})
        job=self.headers.get("X-Print-Id","")
        if not re.fullmatch(r"[A-Za-z0-9-]{12,80}",job): return self.send(400,{"ok":False,"message":"Missing print ID."})
        self.connection.settimeout(30)
        body=self.rfile.read(length)
        if len(body)!=length:return self.send(400,{"ok":False,"message":"Upload was incomplete. Nothing printed."})
        params=urllib.parse.parse_qs(route.query)
        printer=params.get("printer",["s1"])[0]
        if printer not in ["s1","vretti"]:return self.send(400,{"ok":False,"sent":False,"message":"Choose S1 or Vretti."})
        digest=hashlib.sha256(route.path.encode()+b'\0'+route.query.encode()+b'\0'+body).hexdigest()
        if not JOB_LOCK.acquire(blocking=False): return self.send(409,{"ok":False,"message":"Printer is busy. Wait for the current sticker."})
        try:
            if job in jobs:
                previous=jobs[job]
                if previous["digest"]!=digest:return self.send(409,{"ok":False,"message":"That print ID was already used for different content."})
                return self.send(200,previous["result"])
            jobs[job]={"digest":digest,"result":{"ok":False,"message":"This print was already started. Check the sticker before sending it again."}}
            save_jobs()  # Persist before printing: retries never duplicate a started job.
            with tempfile.TemporaryDirectory(prefix="s1-phone-") as tmp:
                if route.path=="/print-text":
                    content=json.loads(body)
                    text=content.get("text")
                    if not isinstance(text,str) or not 0<len(text)<=20000: raise ValueError("Use 1–20,000 characters.")
                    if printer == "vretti":
                        path=Path(tmp)/"sticker.txt";path.write_text(text,encoding="utf-8");args=["--print",str(path)]
                    else: args=["--text",text]
                else:
                    suffix=Path(params.get("name",[""])[0]).suffix.lower()
                    if suffix not in [".png",".jpg",".jpeg",".heic",".webp",".tiff",".gif",".bmp",".pdf",".txt",".md",".json"]: raise ValueError("Use an image, PDF, text, Markdown, or sticker JSON file.")
                    if printer == "vretti" and suffix == ".json": raise ValueError("Vretti supports image, PDF, or text files, not JSON layouts.")
                    path=Path(tmp)/("sticker"+suffix);path.write_bytes(body)
                    args=["--print",str(path)]
                    if params.get("dither",["0"])[0]=="1":args.append("--dither")
                p=subprocess.run([str(VRETTI if printer == "vretti" else BINARY)]+args,capture_output=True,text=True,timeout=200 if printer == "vretti" else 80)
                try: result=json.loads(p.stdout)
                except (ValueError, TypeError): result={"ok":False,"sent":None,"message":"Print result unavailable. Check the printer before sending again."}
            jobs[job]["result"]=result;save_jobs();self.send(200,result)
        except (ValueError,KeyError) as e:
            result={"ok":False,"message":str(e) or "Invalid print data."};jobs[job]["result"]=result;save_jobs();self.send(400,result)
        except subprocess.TimeoutExpired:
            result={"ok":False,"sent":None,"message":"Print timed out. Check the printer before sending again."};jobs[job]["result"]=result;save_jobs();self.send(504,result)
        except OSError:
            result={"ok":False,"sent":False,"message":"Could not start the printer command."};jobs[job]["result"]=result;save_jobs();self.send(503,result)
        finally: JOB_LOCK.release()

if __name__=="__main__":
    hosts=addresses()
    servers=[ThreadingHTTPServer((ip,config["port"]),Handler) for ip in hosts]
    for server in servers:server.daemon_threads=True
    primary=next((ip for ip in hosts if ip!="127.0.0.1"),"127.0.0.1")
    link=f"http://{primary}:{config['port']}/#pair={config['token']}"
    path=STATE/"phone-link.txt"
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
    with os.fdopen(fd,"w") as f:f.write(link+"\n")
    subprocess.run([str(BINARY),"--pairing-page"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    print("S1 bridge ready on office network and localhost",flush=True)
    for server in servers[1:]:threading.Thread(target=server.serve_forever,daemon=True).start()
    servers[0].serve_forever()
