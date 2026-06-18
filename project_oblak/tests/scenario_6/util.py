import hashlib

def transform(text):
    digest = hashlib.sha256(text.encode()).hexdigest()[:8]
    return f"{text}-{digest}"