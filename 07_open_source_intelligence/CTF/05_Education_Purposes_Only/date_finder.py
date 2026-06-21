import hashlib
from datetime import datetime, timedelta

target_hash = "f4d7caf81e33bc156cc3e98cf8095d2e"

start_date = datetime(2005, 1, 1)
end_date = datetime(2010, 10, 31)

current_date = start_date

while current_date <= end_date:
    date_str = current_date.strftime("%d/%m/%Y")
    md5_hash = hashlib.md5(date_str.encode()).hexdigest()

    if md5_hash == target_hash:
        print(f"Match found: {date_str}")
        break

    current_date += timedelta(days=1)
else:
    print("No matching date found.")