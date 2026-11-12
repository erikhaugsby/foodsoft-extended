# Runs RuboCop on the Ruby files this fork changed and reports only offenses on
# lines that were added or changed compared to the upstream base commit.
# Foodsoft upstream has several hundred existing offenses; they are not ours.
require 'json'
require 'open3'

base = ENV.fetch('UPSTREAM_BASE')
diff, status = Open3.capture2('git', 'diff', '-U0', '--diff-filter=AMR', base, 'HEAD', '--',
                              '*.rb', '*.rake', 'Gemfile', ':!.github')
abort 'git diff failed' unless status.success?

changed = Hash.new { |h, k| h[k] = [] }
file = nil
diff.each_line do |line|
  if line.start_with?('+++ ')
    file = line[6..].strip
  elsif (m = line.match(/^@@ -\S+ \+(\d+)(?:,(\d+))? @@/)) && file
    start = m[1].to_i
    count = (m[2] || '1').to_i
    changed[file].concat((start...(start + count)).to_a) if count.positive?
  end
end

if changed.empty?
  puts 'No changed Ruby lines.'
  exit 0
end

out, = Open3.capture2('bundle', 'exec', 'rubocop', '--format', 'json', '--force-exclusion', *changed.keys)
report = JSON.parse(out)

offenses = report['files'].flat_map do |f|
  f['offenses'].select { |o| changed[f['path']].include?(o.dig('location', 'start_line')) }
               .map { |o| [f['path'], o] }
end

offenses.each do |path, o|
  line = o.dig('location', 'start_line')
  col = o.dig('location', 'start_column')
  puts "::error file=#{path},line=#{line},col=#{col}::#{o['cop_name']}: #{o['message']}"
  puts "#{path}:#{line}:#{col}: #{o['cop_name']}: #{o['message']}"
end
puts "#{changed.size} files checked, #{offenses.size} offenses on changed lines."
exit(offenses.empty? ? 0 : 1)
