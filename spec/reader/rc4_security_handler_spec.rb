# typed: false
# coding: utf-8

require 'digest/md5'

describe PDF::Reader::Rc4SecurityHandler do
  let(:key) { "test_encryption_key" }
  let(:handler) { PDF::Reader::Rc4SecurityHandler.new(key) }
  let(:reference) { PDF::Reader::Reference.new(1, 0) }

  describe "#decrypt" do
    it "decrypts data that was encrypted using the PDF spec's object-key algorithm" do
      plaintext = "Hello, World!"
      buf = encrypt_test_data(plaintext, key, reference)

      result = handler.decrypt(buf, reference)
      expect(result).to eq(plaintext)
    end

    it "round trips arbitrary binary data" do
      plaintext = (0..255).to_a.pack("C*")
      buf = encrypt_test_data(plaintext, key, reference)

      result = handler.decrypt(buf, reference)
      expect(result).to eq(plaintext)
    end

    it "returns garbage, not an error, when the key is wrong" do
      wrong_handler = PDF::Reader::Rc4SecurityHandler.new("wrong_key_here!")

      plaintext = "Hello, World!"
      buf = encrypt_test_data(plaintext, key, reference)

      result = wrong_handler.decrypt(buf, reference)
      expect(result).not_to eq(plaintext)
      expect(result).to be_a(String)
    end
  end

  private

  # Helper method to create encrypted test data using the same object-key
  # derivation algorithm the handler itself uses (PDF spec Algorithm 1)
  #
  # @param plaintext [String] the text to encrypt
  # @param encryption_key [String] the encryption key to use
  # @param ref [PDF::Reader::Reference] the PDF reference for key generation
  # @return [String] ciphertext ready for the handler's decrypt method
  def encrypt_test_data(plaintext, encryption_key, ref)
    obj_key = encryption_key.dup
    (0..2).each { |e| obj_key << (ref.id >> e*8 & 0xFF) }
    (0..1).each { |e| obj_key << (ref.gen >> e*8 & 0xFF) }
    length = obj_key.length < 16 ? obj_key.length : 16
    rc4 = PDF::Reader::Rc4.new(Digest::MD5.digest(obj_key)[0, length])
    rc4.encrypt(plaintext)
  end
end
