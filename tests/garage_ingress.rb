require 'yaml'
require 'tmpdir'
require 'fileutils'
require 'open3'

# Exercise parent templates without downloading a dependency. This fixture supplies
# only Garage's documented fullname helper and service-port contract.
Dir.mktmpdir('bookwyrm-garage-ingress') do |dir|
  FileUtils.mkdir_p("#{dir}/templates")
  File.write("#{dir}/Chart.yaml", "apiVersion: v2\nname: ingress-test\nversion: 0.1.0\n")
  values = YAML.safe_load(File.read('values.yaml'))
  values['admin']['email'] = 'test@example.com'
  values['admin']['password'] = 'test-only-password'
  values['garage']['service'] = {'ports'=>{'s3Api'=>3900, 's3Web'=>3902}}
  File.write("#{dir}/values.yaml", YAML.dump(values))
  helpers = Dir['templates/_*.tpl'].reject { |p| p.end_with?('_garage-secret.tpl') }.map { |p| File.read(p) }.join("\n")
  helpers += '{{- define "garage.fullname" -}}{{ .Release.Name }}-garage{{- end -}}'
  File.write("#{dir}/templates/_helpers.tpl", helpers)
  File.write("#{dir}/templates/ingress.yaml", '{{- $_ := set . "Subcharts" (dict "garage" .) -}}' + File.read('templates/garage-ingress.yaml'))
  FileUtils.cp('templates/validate.yaml', "#{dir}/templates/validate.yaml")
  render = lambda do |*args|
    out,status = Open3.capture2e('helm','template','test',dir,
      '--set','garage.enabled=true','--set','s3.ingress.enabled=true',
      '--set','s3.endpointUrl=https://api.tailnet.ts.net',
      '--set','s3.customDomain=assets.tailnet.ts.net',*args)
    raise out unless status.success?
    YAML.load_stream(out).compact
  end
  docs = render.call('--set','ingress.className=tailscale')
  raise 'Expected two ingresses' unless docs.size==2
  docs.each do |ing|
    role=ing['metadata']['name'].end_with?('-api') ? 'api' : 'assets'
    raise 'Host not derived' unless ing.dig('spec','rules',0,'host')=="#{role}.tailnet.ts.net"
    raise 'Class not inherited' unless ing.dig('spec','ingressClassName')=='tailscale'
    raise 'Tailscale rejects mismatched rule and TLS hosts' unless ing.dig('spec','tls',0,'hosts')==[ing.dig('spec','rules',0,'host')]
    backend=ing.dig('spec','rules',0,'http','paths',0,'backend','service')
    raise 'Wrong service' unless backend['name']=='test-garage'
    raise 'Wrong port' unless backend.dig('port','number')==(role=='api' ? 3900 : 3902)
  end
  docs=render.call('--set','s3.ingress.className=traefik','--set','s3.ingress.tls.apiSecretName=api-cert')
  api=docs.find { |i| i['metadata']['name'].end_with?('-api') }
  raise 'TLS override failed' unless api.dig('spec','tls',0)=={'hosts'=>['api.tailnet.ts.net'],'secretName'=>'api-cert'}
  docs=render.call('--set','s3.ingress.tls.enabled=false')
  raise 'TLS disable ignored' if docs.any? { |d| d['spec']['tls'] }
  raise 'External S3 produced Garage ingress' unless render.call('--set','garage.enabled=false').empty?
  raise 'Disable ignored' unless render.call('--set','s3.ingress.enabled=false').empty?
end
puts 'Passed derived hosts, shared ingress class, matching Tailscale rule/TLS hosts, certificate overrides, backend ports, and disabled modes.'
