require 'yaml'
require 'tmpdir'
require 'fileutils'
require 'open3'

Dir.mktmpdir('bookwyrm-helpers') do |dir|
  %w[templates files charts].each { |path| FileUtils.cp_r(path,dir) }
  FileUtils.cp('values.yaml',dir)
  chart=YAML.safe_load(File.read('Chart.yaml'))
  chart['dependencies'].reject! { |d| d['name']=='garage' }
  File.write("#{dir}/Chart.yaml",YAML.dump(chart))
  render=lambda do |*args|
    out,status=Open3.capture2e('helm','template','test',dir,'--set','admin.email=admin@example.com','--set','admin.password=test-password',*args)
    raise out unless status.success?
    YAML.load_stream(out).compact
  end
  ['test','custom-app','x'*63].each do |base|
    docs=render.call('--set',"fullnameOverride=#{base}",'--set','ingress.enabled=true')
    expected=lambda { |suffix| "#{base[0,62-suffix.length].sub(/-+$/, '')}-#{suffix}" }
    web=docs.find { |d| d['kind']=='Deployment' && d.dig('metadata','name')==expected.call('web') }
    raise 'Override not applied to deployment' unless web
    raise 'Selectors renamed' unless web.dig('spec','selector','matchLabels','app.kubernetes.io/instance')=='test'
    ingress=docs.find { |d| d['kind']=='Ingress' }
    raise 'Ingress override mismatch' unless ingress.dig('metadata','name')==base && ingress.dig('spec','rules',0,'http','paths',0,'backend','service','name')==base
    env_ref=web.dig('spec','template','spec','containers',0,'envFrom',0,'secretRef','name')
    raise 'Secret reference mismatch' unless env_ref==expected.call('env') && docs.any? { |d| d['kind']=='Secret' && d.dig('metadata','name')==env_ref }
    job=docs.find { |d| d['kind']=='Job' }
    volume_name=job.dig('spec','template','spec','volumes',0,'configMap','name')
    raise 'Bootstrap ConfigMap reference mismatch' unless docs.any? { |d| d['kind']=='ConfigMap' && d.dig('metadata','name')==volume_name }
    docs.each { |d| raise 'Name exceeds 63 characters' if d.dig('metadata','name').length>63 }
    script=web.dig('spec','template','spec','initContainers',0,'args',0)
    out,status=Open3.capture2e('/bin/sh','-n',stdin_data:script)
    raise "Invalid startup shell: #{out}" unless status.success?
  end
  docs=render.call('--set','postgresql.enabled=true','--set','postgresql.fullnameOverride=',
    '--set','postgresql.primary.service.ports.postgresql=5454',
    '--set','redisBroker.enabled=true','--set','redisBroker.fullnameOverride=',
    '--set','redisBroker.master.service.ports.redis=6380',
    '--set','redisActivity.enabled=true','--set','redisActivity.fullnameOverride=',
    '--set','redisActivity.master.service.ports.redis=6381')
  web=docs.find { |d| d['kind']=='Deployment' && d.dig('metadata','name')=='test-web' }
  env=web.dig('spec','template','spec','containers',0,'env').to_h { |e| [e['name'],e['value']] }
  [['POSTGRES_HOST','PGPORT','5454'],['REDIS_BROKER_HOST','REDIS_BROKER_PORT','6380'],['REDIS_ACTIVITY_HOST','REDIS_ACTIVITY_PORT','6381']].each do |host,port,expected|
    svc=docs.find { |d| d['kind']=='Service' && d.dig('metadata','name')==env[host] }
    raise "Wrong #{host}: #{env[host]}" unless svc
    raise "Wrong #{port}" unless env[port]==expected && svc.dig('spec','ports').any? { |p| p['port'].to_s==expected }
  end
  ['ftp://storage.example.com','not-a-url','https:///'].each do |url|
    out,status=Open3.capture2e('helm','template','test',dir,'--set',"s3.endpointUrl=#{url}")
    raise 'Malformed external S3 URL accepted' if status.success? || !out.include?('http or https URL with a hostname')
  end
end
# Duplicate definitions within the parent chart are always a mistake.
names=Dir['templates/_*.tpl'].flat_map { |path| File.read(path).scan(/define\s+"([^"]+)"/).flatten }
raise 'Duplicate parent helper definitions' unless names.uniq.length==names.length
puts 'Passed naming defaults/overrides, suffix lengths, stable selectors, references, shell syntax, real dependency service ports, and S3 validation.'
