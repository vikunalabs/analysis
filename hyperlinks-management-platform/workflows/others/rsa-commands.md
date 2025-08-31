
● Here are the commands to generate RSA key pair for JWT:

  Generate RSA Key Pair

# Create keys directory
mkdir -p keys

# Generate private key (2048-bit RSA)
openssl genpkey -algorithm RSA -out keys/private_key.pem -pkeyopt rsa_keygen_bits:2048

# Generate public key from private key
openssl rsa -pubout -in keys/private_key.pem -out keys/public_key.pem

# Convert to Base64
base64 -w 0 keys/private_key.pem > keys/private_key_base64.txt
base64 -w 0 keys/public_key.pem > keys/public_key_base64.txt

# Display the keys
echo "Private Key Base64:"
cat keys/private_key_base64.txt

echo -e "\n\nPublic Key Base64:"
cat keys/public_key_base64.txt

  Set Environment Variables

  # Add to your .env or export directly
  export JWT_PRIVATE_KEY=$(cat keys/private_key_base64.txt)
  export JWT_PUBLIC_KEY=$(cat keys/public_key_base64.txt)

  Security Note:
  - Keep private_key.pem secure and never commit to version control
  - Add keys/ directory to .gitignore
  - For production, use secure key management (AWS KMS, Azure Key Vault, etc.)
