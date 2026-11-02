"""Write a cask for an already notarized release archive. Never use :no_check."""
import hashlib
import sys
from pathlib import Path
archive, output = map(Path, sys.argv[1:])
root = Path(__file__).resolve().parent.parent
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
text = (root / "packaging/menu-veil.rb.in").read_text().replace("@SHA256@", checksum)
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(text)
print(f"Wrote {output} with SHA-256 {checksum}")
