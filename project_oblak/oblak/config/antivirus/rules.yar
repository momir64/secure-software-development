rule PythonReverseShell {
    meta:
        description = "Python reverse shell patterns"
        severity = "critical"
    strings:
        $s1 = "socket.socket" ascii
        $s2 = "connect(" ascii
        $s3 = "SOCK_STREAM" ascii
        $s4 = "dup2(" ascii
        $cmd1 = "/bin/sh" ascii
        $cmd2 = "/bin/bash" ascii
        $cmd3 = "cmd.exe" ascii
    condition:
        ($s1 and $s2 and $s3) and ($s4 or $cmd1 or $cmd2 or $cmd3)
}

rule ObfuscatedExec {
    meta:
        description = "Obfuscated exec/eval — encoded payload execution"
        severity = "high"
    strings:
        $b64    = "base64.b64decode" ascii
        $b64_2  = "b64decode" ascii
        $rot    = "codecs.decode" ascii
        $chr    = /chr\(\d+\)\s*\+/ ascii
        $exec1  = "exec(" ascii
        $exec2  = "eval(" ascii
        $compile = "compile(" ascii
    condition:
        ($exec1 or $exec2 or $compile) and ($b64 or $b64_2 or $rot or $chr)
}

rule ForkBomb {
    meta:
        description = "Fork bomb / resource exhaustion"
        severity = "critical"
    strings:
        $fork1 = "os.fork()" ascii
        $fork2 = "multiprocessing.Process" ascii
        $while  = "while True" ascii
        $while2 = "while 1" ascii
    condition:
        ($fork1 or $fork2) and ($while or $while2)
}

rule SuspiciousNetworkExfil {
    meta:
        description = "Possible data exfiltration via HTTP"
        severity = "high"
    strings:
        $req1 = "requests.post(" ascii
        $req2 = "urllib.request.urlopen(" ascii
        $req3 = "http.client.HTTPConnection(" ascii
        $env1 = "os.environ" ascii
        $env2 = "os.getenv(" ascii
        $read1 = "open(" ascii
        $read2 = ".read()" ascii
    condition:
        ($req1 or $req2 or $req3) and ($env1 or $env2) and ($read1 or $read2)
}

rule CryptoMiner {
    meta:
        description = "Cryptocurrency miner indicators"
        severity = "high"
    strings:
        $pool1  = "stratum+tcp" ascii
        $pool2  = "mining.subscribe" ascii
        $pool3  = "xmrig" ascii nocase
        $pool4  = "monero" ascii nocase
        $hash1  = "hashlib.sha256" ascii
        $nonce  = "nonce" ascii
    condition:
        ($pool1 or $pool2 or $pool3 or $pool4) or
        (3 of ($hash1, $nonce, $pool1, $pool2))
}

rule PrivilegeEscalation {
    meta:
        description = "Privilege escalation attempt"
        severity = "critical"
    strings:
        $suid   = "os.chmod" ascii
        $setuid = "os.setuid(0)" ascii
        $sudo   = "sudo" ascii
        $proc   = "/proc/self" ascii
        $cgroup = "/sys/fs/cgroup" ascii
        $ns     = "unshare" ascii
    condition:
        $setuid or ($proc and ($suid or $sudo)) or $cgroup or $ns
}

rule OblakSandboxEscape {
    meta:
        description = "Firecracker/OverlayFS sandbox escape patterns"
        severity = "critical"
    strings:
        $overlay = "overlay" ascii
        $proc_self = "/proc/self" ascii
        $proc_mem  = "/proc/mem" ascii
        $cgroup    = "/sys/fs/cgroup" ascii
        $devmem    = "/dev/mem" ascii
        $nsenter   = "nsenter" ascii
        $unshare   = "unshare" ascii
    condition:
        any of them
}

rule OblakRuntimeInstall {
    meta:
        description = "Attempts to install packages at runtime (supply chain risk)"
        severity = "high"
    strings:
        $pip1  = "pip install" ascii
        $pip2  = "pip3 install" ascii
        $uv    = "uv pip install" ascii
        $subp  = "subprocess" ascii
        $os_s  = "os.system" ascii
    condition:
        ($pip1 or $pip2 or $uv) and ($subp or $os_s)
}

rule EICARTest {
    meta:
        description = "EICAR antivirus test string"
        severity = "critical"

    strings:
        $eicar = "EICAR-STANDARD-ANTIVIRUS-TEST-FILE"

    condition:
        $eicar
}