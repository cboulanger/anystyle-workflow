class Foo
  @instance_var = ENV['TESTTEST']

  class << self
    def test
      puts @instance_var
    end
  end
end

Foo.test