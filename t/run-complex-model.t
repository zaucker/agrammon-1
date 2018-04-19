use Test;
use Agrammon::DataSource::CSV;
use Agrammon::ModelCache;
use Agrammon::Model::Parameters;
use Agrammon::OutputFormatter::CSV;
use Agrammon::TechnicalParser;

my $path = $*PROGRAM.parent.add('test-data/Models/hr-inclNOx/');
my $top = 'Total';
my $model;
lives-ok { $model = load-model-using-cache($*HOME.add('.agrammon'), $path, $top)}, "Load model from $top";

my $fh = open $*PROGRAM.parent.add('test-data/complex-model-input.csv');
my @datasets = Agrammon::DataSource::CSV.new().read($fh);
is @datasets.elems, 1, 'Got the one expected data set to run';
$fh.close;

my $params;
lives-ok
    { $params = parse-technical($*PROGRAM.parent.add('test-data/Models/hr-inclNOx/technical.cfg').slurp) },
    'Parsed technical file';
isa-ok $params, Agrammon::Model::Parameters, 'Correct type for technical data';

my $output;
lives-ok
    {
        $output = $model.run(
            input => @datasets[0],
            technical => %($params.technical.map(-> %module {
                %module.keys[0] => %(%module.values[0].map({ .name => .value }))
            }))
        )
    },
    'Successfully executed model';

# TODO: Test the output is correct

done-testing;
