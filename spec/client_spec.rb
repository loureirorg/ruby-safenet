require 'spec_helper'

describe SafeNet do

  before do
    @safe = SafeNet::Client.new(permissions: ["SAFE_DRIVE_ACCESS", "LOW_LEVEL_API"])
  end

  describe ".auth" do
    it "should ask for permissions" do
      resp = @safe.auth.auth
      expect(resp["token"]).not_to be_empty
    end
  end

  describe SafeNet::Immutable do

    describe ".get_writer_handle" do
      context "given no params" do
        it "should return an integer" do
          hnd = @safe.immutable.get_writer_handle
          expect(hnd).to be_a(Integer)

          # free mem
          @safe.immutable.drop_writer_handle(hnd)
        end
      end
    end
    
  end

  describe SafeNet::Cipher do

    describe ".get_handle" do
      context "given no params" do
        it "should return an integer" do
          hnd = @safe.cipher.get_handle
          expect(hnd).to be_a(Integer)

          # free mem
          @safe.cipher.drop_handle(hnd)
        end
      end
    end

    describe ".drop_handle" do
      context "given an invalid handle" do
        it "should return an error-hash" do
          res = @safe.cipher.drop_handle(-1)
          expect(res).to have_key("errorCode")
        end
      end

      context "given a valid handle" do
        it "should return true" do
          hnd = @safe.cipher.get_handle
          res = @safe.cipher.drop_handle(hnd)
          expect(res).to be true
        end
      end
    end
  end
end
