import requests

def hello_world():
    with open("/var/task/file.txt", "r", encoding="utf-8") as file:
        content = file.read()
    return content

def fetch_todo():
    return requests.get("https://jsonplaceholder.typicode.com/todos/1").json()