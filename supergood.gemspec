require_relative './lib/supergood/version.rb'

Gem::Specification.new do |s|
  s.name = 'supergood'
  s.version = Supergood::VERSION
  s.date = '2023-03-13'
  s.authors = ['Alex Klarfeld']
  s.email = 'alex@supergood.ai'
  s.license = 'Nonstandard'
  s.summary = 'Supergood - API monitoring'
  s.files = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  s.bindir = 'exe'
  s.executables = s.files.grep(%r{^exe/}) { |f| File.basename(f) }
  s.require_paths = ['lib']
  s.homepage = 'https://supergood.ai'
  s.metadata = { 'source_code_uri' => 'https://github.com/supergoodsystems/supergood-rb', 'license' => 'BUSL-1.1' }
  s.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  s.add_runtime_dependency 'base64', '~> 0.1'
  s.add_runtime_dependency 'digest', '~> 3.1', '>= 3.1.1'
  s.add_runtime_dependency 'dotenv', '~> 2.8', '>= 2.8.1'
  s.add_runtime_dependency 'json', '~> 2.6', '>= 2.6.3'
  s.add_runtime_dependency 'logger', '~> 1.5', '>= 1.6'
  s.add_runtime_dependency 'rudash', '~> 4.1', '>= 4.1.2'
  s.add_runtime_dependency 'securerandom', '~> 0.2', '>= 0.2.2'
  s.add_runtime_dependency 'stringio', '~> 3.0'
  s.add_runtime_dependency 'uri', '~> 0.12'
  s.add_runtime_dependency 'zlib', '~> 3.0'

  s.add_development_dependency 'faraday', '~> 2.7', '>= 2.7.4'
  s.add_development_dependency 'http', '~> 5.1', '>= 5.1.1'
  s.add_development_dependency 'httparty', '~> 0.21.0'
  s.add_development_dependency 'rest-client', '~> 2.1'
  s.add_development_dependency 'rspec', '~> 3.12'
  s.add_development_dependency 'webmock', '~> 3.18', '>= 3.18.1'

end

