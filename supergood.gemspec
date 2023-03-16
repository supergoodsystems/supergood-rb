require_relative './lib/version.rb'

Gem::Specification.new do |s|
  s.name = 'supergood'
  s.version = Supergood::VERSION
  s.date = '2023-03-13'
  s.authors = ['Alex Klarfeld']
  s.email = 'alex@supergood.ai'
  s.license = 'Business Source License 1.1'
  s.summary = 'Supergood - API monitoring'
  s.files = Dir.glob('{lib}/**/*')
  s.homepage = 'https://supergood.ai'
  s.metadata = { 'source_code_uri' => 'https://github.com/supergoodsystems/supergood-rb' }
  s.required_ruby_version = '>= 2.1.0'
end

