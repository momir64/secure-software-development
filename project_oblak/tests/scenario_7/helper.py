from pathlib import Path

def read_message():
    with open("message.txt", "r") as file:
        return file.read().strip()