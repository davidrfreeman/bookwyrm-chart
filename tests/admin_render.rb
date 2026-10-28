require 'yaml'
require 'tmpdir'
require 'fileutils'
require 'open3'

# Test the real parent templates in external-service mode, without fetching Garage.
Dir.mktmpdir('bookwyrm-admin-render') do |dir|
  %w[templates files charts].each { |path| FileUtils.cp_r(path,dir) }
  FileUtils.cp('values.yaml',dir)
  chart=YAML.safe_load(File.read('Chart.yaml'))
  chart['dependencies'].reject! { |d| d['name']=='garage' }
  File.write("#{dir}/Chart.yaml",YAML.dump(chart))
  render=lambda do |*args|
    Open3.capture2e('helm','template','test',dir,*args)
  end
  out,status=render.call
  raise 'Missing required email accepted' if status.success? || !out.include?('admin.email is required')
  out,status=render.call('--set','admin.email=admin@example.com')
  raise 'Missing required password accepted' if status.success? || !out.include?('admin.password')
  ['', 'external'].each do |mode|
    args=['--set','admin.email=admin@example.com','--set','admin.username=owner']
    args += mode=='' ? ['--set-string','admin.password=unique-test-password'] : ['--set','admin.existingSecret=admin-credentials','--set','admin.passwordSecretKey=pass','--set','migration.enabled=false']
    out,status=render.call(*args)
    raise out unless status.success?
    docs=YAML.load_stream(out).compact
    job=docs.find { |d| d['kind']=='Job' && d.dig('metadata','name')=='test-init-1' }
    raise 'Initialization Job missing' unless job
    container=job.dig('spec','template','spec','containers',0)
    env=container['env'].to_h { |e| [e['name'],e] }
    raise 'Wrong admin identity' unless env.dig('BOOKWYRM_ADMIN_USERNAME','value')=='owner'
    expected= mode=='' ? {'name'=>'test-admin','key'=>'password'} : {'name'=>'admin-credentials','key'=>'pass'}
    raise 'Wrong password reference' unless env.dig('BOOKWYRM_ADMIN_PASSWORD','valueFrom','secretKeyRef')==expected
    raise 'Bootstrap not executed' unless container['args'][0].include?('admin-bootstrap.py')
    if mode=='external'
      raise 'External migration wait missing' unless container['args'][0].include?('externally managed migrations')
      raise 'Unexpected admin Secret' if docs.any? { |d| d['kind']=='Secret' && d.dig('metadata','name')=='test-admin' }
    end
    docs.select { |d| d['kind']=='Deployment' }.each do |dep|
      pod=dep.dig('spec','template','spec')
      raise 'Bootstrap password leaked into deployment' if YAML.dump(dep).include?('BOOKWYRM_ADMIN_PASSWORD') || YAML.dump(dep).include?('unique-test-password')
      raise 'Admin gate missing' unless pod['initContainers'][0]['args'][0].include?('Admin initialization pending')
    end
    # The password may exist only in the separate admin Secret, not command text.
    raise 'Password in command args' if YAML.dump(job).include?('unique-test-password')
  end
  [
    [[], 'test', true, false],
    [['--set','serviceAccount.name=app-identity'], 'app-identity', true, false],
    [['--set','fullnameOverride=custom'], 'custom', true, false],
    [['--set','serviceAccount.create=false','--set','serviceAccount.name=existing'], 'existing', false, false],
    [['--set','serviceAccount.create=false'], 'default', false, false],
    [['--set','serviceAccount.automountServiceAccountToken=true'], 'test', true, true]
  ].each do |args,name,created,token|
    out,status=render.call('--set','admin.email=admin@example.com','--set','admin.password=test-password',*args)
    raise out unless status.success?
    docs=YAML.load_stream(out).compact
    accounts=docs.select { |d| d['kind']=='ServiceAccount' }
    raise 'Wrong ServiceAccount creation behavior' unless accounts.size==(created ? 1 : 0)
    if created
      raise 'Wrong account name or token default' unless accounts[0].dig('metadata','name')==name && accounts[0]['automountServiceAccountToken']==token
    end
    pods=docs.select { |d| ['Deployment','Job'].include?(d['kind']) }.map { |d| d.dig('spec','template','spec') }
    raise 'Application workload omitted' unless pods.size==4
    raise 'Wrong workload identity/token setting' unless pods.all? { |pod| pod['serviceAccountName']==name && pod['automountServiceAccountToken']==token }
    raise 'Unneeded application RBAC' if docs.any? { |d| ['Role','RoleBinding','ClusterRole','ClusterRoleBinding'].include?(d['kind']) }
  end
end
puts 'Passed required admin validation, Secret modes, password isolation, external migrations, startup gates, and ServiceAccount modes.'
