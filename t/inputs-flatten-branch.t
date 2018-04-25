use Agrammon::Inputs;
use Test;

given Agrammon::Inputs::Distribution.new -> $dist {
    lives-ok { $dist.add-single-input('Foo::Foo', 'single', 42) },
            'Can add single input to input distribution';
    lives-ok { $dist.add-multi-input('Foo::Bar', 'Instance A', 'Baz', 'val', 101) },
            'Can add multi input to input distribution';
    lives-ok
            {
                $dist.add-multi-input-flattened('Foo::Bar', 'Instance B', 'Baz',
                    'kind', { abc => 10, def => 90 })
            },
            'Can add flattened input';
    throws-like
            {
                $dist.add-multi-input-flattened('Foo::Bar', 'Instance B', 'Baz',
                        'kind', { abc => 10, def => 90 })
            },
            X::Agrammon::Inputs::Distribution::AlreadyFlattened,
            'Cannot add duplicate flattened input';
    lives-ok
            {
                $dist.add-multi-input-flattened('Foo::Bar', 'Instance B', 'Baz',
                        'volume', { quiet => 50, medium => 30, loud => 20 })
            },
            'Can add second flattened input';
    throws-like
            {
                $dist.add-multi-input-flattened('Foo::Bar', 'Instance B', 'Baz',
                        'something', { quiet => 60, medium => 30, loud => 20 })
            },
            X::Agrammon::Inputs::Distribution::BadSum,
            'Flattened input must sum to 100 (1)';
    throws-like
            {
                $dist.add-multi-input-flattened('Foo::Bar', 'Instance B', 'Baz',
                        'something', { quiet => 30, medium => 30, loud => 20 })
            },
            X::Agrammon::Inputs::Distribution::BadSum,
            'Flattened input must sum to 100 (2)';

    lives-ok
            {
                $dist.add-multi-input-branched('Foo::Bar', 'Instance C', 'Baz',
                    'kind', 'volume', [[20, 10, 20],[30, 20, 0]])
            },
            'Can add branched multi input';
    throws-like
            {
                $dist.add-multi-input-branched('Foo::Bar', 'Instance C', 'Baz',
                        'other-kind', 'volume', [[20, 10, 20],[30, 20, 0]])
            },
            X::Agrammon::Inputs::Distribution::AlreadyBranched,
            'Cannot add duplicate branched input';
    throws-like
            {
                $dist.add-multi-input-branched('Foo::Bar', 'Instance B', 'Baz',
                        'kind', 'volume', [[20, 10, 20],[30, 20, 0]])
            },
            X::Agrammon::Inputs::Distribution::AlreadyFlattened,
            'Cannot add branched input that covers a flattened input';
    throws-like
            {
                $dist.add-multi-input-flattened('Foo::Bar', 'Instance C', 'Baz',
                        'kind', { abc => 10, def => 90 })
            },
            X::Agrammon::Inputs::Distribution::AlreadyBranched,
            'Cannot add flattend input that covers a branched input';
    throws-like
            {
                $dist.add-multi-input-branched('Foo::Bar', 'Instance C', 'Baz',
                        'aaa', 'bbb', [[20, 10, 30],[30, 20, 10]])
            },
            X::Agrammon::Inputs::Distribution::BadSum,
            'Branch matrix must sum to 100 (1)';
    throws-like
            {
                $dist.add-multi-input-branched('Foo::Bar', 'Instance C', 'Baz',
                        'aaa', 'bbb', [[10, 5, 10],[10, 20, 10]])
            },
            X::Agrammon::Inputs::Distribution::BadSum,
            'Branch matrix must sum to 100 (2)';
}

done-testing;
