"""
One-time setup script to generate bcrypt password hash.

Usage:
    python scripts/hash_password.py

The script will prompt you to enter a password (input is hidden).
Copy the printed hash into your .env file as ADMIN_PASSWORD_HASH.

NEVER store the plain password anywhere.
"""

import getpass
import sys

try:
    import bcrypt
except ImportError:
    print("ERROR: bcrypt not installed. Run: pip install bcrypt")
    sys.exit(1)


def main() -> None:
    print("=" * 50)
    print("  Shree Ganadhish — Password Hash Generator")
    print("=" * 50)
    print()

    password = getpass.getpass("Enter admin password: ")
    if not password:
        print("ERROR: Password cannot be empty.")
        sys.exit(1)

    confirm = getpass.getpass("Confirm admin password: ")
    if password != confirm:
        print("ERROR: Passwords do not match.")
        sys.exit(1)

    hashed = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt(rounds=12))

    print()
    print("=" * 50)
    print("  Copy this into your .env file:")
    print("=" * 50)
    print(f"\nADMIN_PASSWORD_HASH={hashed.decode('utf-8')}\n")
    print("=" * 50)
    print("  DONE. Do not save the plain password anywhere.")
    print("=" * 50)


if __name__ == "__main__":
    main()
