require 'yaml'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'base64'

Dir.mktmpdir('bookwyrm-garage-secret') do |dir|
  FileUtils.mkdir_p("#{dir}/templates")
  File.write("#{dir}/Chart.yaml", "apiVersion: v2\nname: secret-test\nversion: 0.1.0\n")
  FileUtils.cp('templates/_garage-secret.tpl',"#{dir}/templates/_garage-secret.tpl")
  File.write("#{dir}/templates/_fixture.tpl", '{{- define "garage.secretName" -}}garage-secret{{- end -}}')
  File.write("#{dir}/templates/check.yaml", <<~TPL)
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: check
    data:
      first: {{ include "garage.secret.content" . | quote }}
      second: {{ include "garage.secret.content" . | quote }}
      retained: {{ include "bookwyrm.garageSecretData" (dict "config" .Values.garage.secret "previous" .Values.previous "webui" .Values.webui) | quote }}
  TPL
  defaults={'garage'=>{'secret'=>{'create'=>true,'rpcSecret'=>'','adminToken'=>''}},'webui'=>{'enabled'=>false,'auth'=>{'enabled'=>false,'existingSecret'=>'','userPassHash'=>''}},'previous'=>{'rpcSecret'=>Base64.strict_encode64('existing-rpc'),'adminToken'=>Base64.strict_encode64('existing-admin')}}
  File.write("#{dir}/values.yaml",YAML.dump(defaults))
  render=lambda do |*args|
    out,status=Open3.capture2e('helm','template','test',dir,*args)
    raise out unless status.success?
    YAML.load_stream(out).compact.first.fetch('data')
  end
  generated=render.call
  raise 'Different Secret/checksum data in one render' unless generated['first']==generated['second']
  YAML.safe_load(generated['first']).each_value { |v| raise 'Invalid generated credential' unless Base64.strict_decode64(v).match?(/\A[0-9a-f]{64}\z/) }
  raise 'Existing credentials were rotated' unless YAML.safe_load(generated['retained'])==defaults['previous']
  raise 'Retained checksum changes across renders' unless generated['retained']==render.call['retained']
  args=['--set','garage.secret.rpcSecret=fixed-rpc','--set','garage.secret.adminToken=fixed-admin']
  fixed=render.call(*args)
  raise 'Explicit values do not produce stable checksum' unless fixed['first']==render.call(*args)['first']
  raise 'Explicit value did not override existing credential' unless YAML.safe_load(fixed['retained'])['rpcSecret']==Base64.strict_encode64('fixed-rpc')
  changed=render.call('--set','garage.secret.rpcSecret=rotated','--set','garage.secret.adminToken=fixed-admin')
  raise 'Rotation did not change checksum' if changed['first']==fixed['first']
  external=render.call('--set','garage.secret.create=false')
  raise 'External Secret checksum unstable' unless external['first']=='existingSecret: garage-secret' && external['first']==render.call('--set','garage.secret.create=false')['first']
end
puts 'Passed credential reuse, consistent per-render Secret/checksum data, explicit rotation, and external Secret stability.'
