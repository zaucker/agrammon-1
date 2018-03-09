use v6;
use Agrammon::DB::User;

class Agrammon::DB::Dataset {
    has Int $.id;
    has Str $.name;
    has Bool $.read-only;
    has Str $.model;
    has Str $.comment;
    has Str $.version;
    has DateTime $.mod-date;
    has Agrammon::DB::User $.user;

    method create {
        ...
    }

    method load(Str $name) {
        ...
    }

    method data {
        ...
    }
    
}
