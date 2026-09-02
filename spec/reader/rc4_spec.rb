# typed: false
# coding: utf-8

describe PDF::Reader::Rc4 do
  # Well known RC4 test vectors. See:
  # https://en.wikipedia.org/wiki/RC4#Test_vectors
  describe "#decrypt" do
    it "matches the 'Key'/'Plaintext' test vector" do
      rc4 = PDF::Reader::Rc4.new("Key")
      result = rc4.decrypt("Plaintext")
      expect(result.unpack("H*")[0]).to eq("bbf316e8d940af0ad3")
    end

    it "matches the 'Wiki'/'pedia' test vector" do
      rc4 = PDF::Reader::Rc4.new("Wiki")
      result = rc4.decrypt("pedia")
      expect(result.unpack("H*")[0]).to eq("1021bf0420")
    end

    it "matches the 'Secret'/'Attack at dawn' test vector" do
      rc4 = PDF::Reader::Rc4.new("Secret")
      result = rc4.decrypt("Attack at dawn")
      expect(result.unpack("H*")[0]).to eq("45a01f645fc35b383552544b9bf5")
    end

    it "raises ArgumentError instead of ZeroDivisionError for an empty key" do
      expect { PDF::Reader::Rc4.new("") }.to raise_error(ArgumentError, "key must not be empty")
    end

    it "is symmetric - decrypting the ciphertext returns the original plaintext" do
      plaintext = "Plaintext"
      ciphertext = PDF::Reader::Rc4.new("Key").decrypt(plaintext)
      roundtrip  = PDF::Reader::Rc4.new("Key").decrypt(ciphertext)
      expect(roundtrip).to eq(plaintext)
    end

    it "aliases encrypt to the same operation as decrypt" do
      key = "Secret"
      plaintext = "Attack at dawn"
      encrypted = PDF::Reader::Rc4.new(key).encrypt(plaintext)
      decrypted = PDF::Reader::Rc4.new(key).decrypt(plaintext)
      expect(encrypted).to eq(decrypted)
    end
  end
end
