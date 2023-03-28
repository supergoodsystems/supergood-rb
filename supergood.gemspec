require_relative './lib/supergood/version.rb'

Gem::Specification.new do |s|
  s.name = 'supergood'
  s.version = Supergood::VERSION
  s.date = '2023-03-13'
  s.authors = ['Alex Klarfeld']
  s.email = 'alex@supergood.ai'
  s.license = 'Nonstandard'
  s.summary = 'Supergood - API monitoring'
  s.files = Dir.glob('{lib}/**/*')
  s.homepage = 'https://supergood.ai'
  s.metadata = { 'source_code_uri' => 'https://github.com/supergoodsystems/supergood-rb', 'license' => 'BUSL-1.1' }
  s.required_ruby_version = '>= 2.1.0'

  s.add_dependency 'rudash', '~> 4.0', '>= 4.0.2'
  s.add_dependency 'faraday', '~> 2.7', '>= 2.7.4'

  s.add_development_dependency 'rest-client'
  s.add_development_dependency 'httparty'
  s.add_development_dependency 'http'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'webmock'

end

