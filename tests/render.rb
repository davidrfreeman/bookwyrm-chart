require 'yaml'
require 'json'
require 'digest'
require 'open3'
require 'time'
require 'base64'

def render(*args)
  out, status = Open3.capture2e('helm', 'template', 'bookwyrm-bookwyrm', '.', '--set', 'admin.email=test@example.com', '--set', 'admin.password=test-only-password', *args)
  raise out unless status.success?
  YAML.load_stream(out).compact
end

def check_app(docs, credential_secret)
  deployments = docs.select { |d| d['kind'] == 'Deployment' }
  raise 'Expected web, worker, beat only' unless deployments.size == 3
  raise 'Local app PVCs still exist' if docs.any? { |d| d['kind'] == 'PersistentVolumeClaim' }
  web = deployments.find { |d| d.dig('metadata', 'name') == 'bookwyrm-bookwyrm-web' }
  raise 'Unexpected sidecar' unless web.dig('spec','template','spec','containers').map { |c| c['name'] } == ['web']
  raise 'Web still mounts files' if web.dig('spec','template','spec','volumes')
  workloads = deployments + docs.select { |d| d['kind'] == 'Job' && d.dig('metadata','name') =~ /-init-/ }
  workloads.each do |workload|
    spec = workload.dig('spec','template','spec')
    (spec.fetch('initContainers',[]) + spec.fetch('containers')).each do |container|
      env = container.fetch('env').to_h { |e| [e['name'], e] }
      %w[USE_S3 USE_S3_FOR_EXPORTS].each { |key| raise "Missing #{key}" unless env.dig(key,'value') == 'true' }
      raise 'Missing private exports bucket' unless env.dig('EXPORTS_STORAGE_BUCKET_NAME','value') == 'bookwyrm-exports'
      if credential_secret
        %w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY].each do |key|
          raise 'Wrong S3 Secret' unless env.dig(key,'valueFrom','secretKeyRef','name') == credential_secret
        end
      end
    end
  end
  docs.select { |d| d['kind']=='Service' && ['bookwyrm-bookwyrm','bookwyrm-bookwyrm-web'].include?(d.dig('metadata','name')) }.each do |service|
    raise 'Service not targeting Gunicorn' unless service.dig('spec','ports',0,'targetPort') == 'gunicorn'
  end
  ingress = docs.find { |d| d['kind']=='Ingress' && d.dig('metadata','name')=='bookwyrm-bookwyrm' }
  raise 'Wrong ingress backend' unless ingress.dig('spec','rules',0,'http','paths',0,'backend','service','name')=='bookwyrm-bookwyrm'
end

base = ['--set','ingress.enabled=true']
check_app(render(*base, '--set', 'web.replicas=2'), nil)
external = render(*base, '--set', 'existingSecret=app-secret', '--set', 's3.existingSecret=s3-secret')
check_app(external, 's3-secret')
raise 'Unexpected generated application Secret' if external.any? { |d| d['kind']=='Secret' && d.dig('metadata','name')=='bookwyrm-bookwyrm-env' }
all = render(*base, '--set', 'postgresql.enabled=true', '--set', 'redisBroker.enabled=true', '--set', 'redisActivity.enabled=true', '--set', 'garage.enabled=true')
# Dependency Deployments/Jobs are absent with these standalone dependencies.
check_app(all, 'bookwyrm-bookwyrm-garage-s3')
server = all.find { |d| d['kind']=='StatefulSet' && d.dig('metadata','name')=='bookwyrm-bookwyrm-garage' }
raise 'Expected one Garage replica' unless server.dig('spec','replicas') == 1
job = all.find { |d| d['kind']=='Job' && d.dig('metadata','name')=='bookwyrm-bookwyrm-garage-bootstrap-1' }
raise 'Setup Job missing or hook' unless job && !job.dig('metadata','annotations','helm.sh/hook')
raise 'Setup needs bootstrap credentials' if job.dig('spec','template','spec','containers',0,'envFrom')
role = all.find { |d| d['kind']=='Role' && d.dig('metadata','name')=='bookwyrm-bookwyrm-garage-bootstrap' }
raise 'Excess RBAC' unless role['rules']==[{'apiGroups'=>[''],'resources'=>['secrets'],'resourceNames'=>['bookwyrm-bookwyrm-garage-s3'],'verbs'=>['patch']}]
# Confirm the dependency lock digest follows Helm's HashReq serialization.
chart=YAML.safe_load(File.read('Chart.yaml'))
lock=YAML.safe_load(File.read('Chart.lock'))
normalize=lambda { |deps| deps.map { |d| %w[name version repository condition tags enabled import-values alias].to_h { |k| [k,d[k]] }.reject { |k,v| v.nil? || v==false || v=='' && !%w[name repository].include?(k) } } }
serialized=JSON.generate([normalize.call(chart['dependencies']),normalize.call(lock['dependencies'])]).gsub('>','\\u003e').gsub('<','\\u003c').gsub('&','\\u0026')
raise 'Stale lock file' unless lock['digest']=='sha256:'+Digest::SHA256.hexdigest(serialized)
out,status=Open3.capture2e('helm','template','test','.', '--set', 'admin.email=test@example.com', '--set', 'admin.password=test-only-password', '--set', 's3.exportsBucket=bookwyrm')
raise 'Public exports accepted' if status.success? || !out.include?('must differ')
puts 'Passed external/S3 Secret modes, bundled dependencies, no Nginx/PVCs, routing, bootstrap RBAC, private exports, and lock consistency.'
