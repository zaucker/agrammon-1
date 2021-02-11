use v6;
use Agrammon::Config;
use Agrammon::DataSource::DB;
use Agrammon::DB::Dataset;
use Agrammon::DB::Datasets;
use Agrammon::DB::User;
use Agrammon::DB::Tags;
use Agrammon::Email;
use Agrammon::Model;
use Agrammon::OutputsCache;
use Agrammon::OutputFormatter::Excel;
use Agrammon::OutputFormatter::JSON;
use Agrammon::OutputFormatter::PDF;
use Agrammon::OutputFormatter::Text;
use Agrammon::Performance;
use Agrammon::Timestamp;
use Agrammon::Web::SessionUser;
use Agrammon::UI::Web;

class Agrammon::Web::Service {
    has Agrammon::Config $.cfg;
    has Agrammon::Model  $.model;
    has %.technical-parameters;
    has Agrammon::UI::Web $.ui-web .= new(:$!model);
    has Agrammon::OutputsCache $!outputs-cache .= new;

    # return config hash as expected by Web GUI
    method get-cfg() {
        my %gui   = $!cfg.gui;
        my %model = $!cfg.model;
        my %cfg = (
            guiVariant   => %gui<variant>,
            modelVariant => %model<variant>,
            title        => %gui<title>,
            variant      => %model<variant>,
            version      => %model<version>,
            submission   => %gui<submission>,
        );
        return %cfg;
    }

    # return list of datasets as expected by Web GUI
    method get-datasets(Agrammon::Web::SessionUser $user, Str $version) {
        return Agrammon::DB::Datasets.new(:$user, :$version).load.list;
    }

    method delete-datasets(Agrammon::Web::SessionUser $user, @datasets) {
        return Agrammon::DB::Datasets.new(:$user).delete(@datasets);
    }

    # return list of datasets as expected by Web GUI
    method send-datasets(Agrammon::Web::SessionUser $user, @datasets, $recipient, $language) {
        # prevent SPAMing
        die X::Agrammon::DB::User::UnknownUser.new(:username($recipient)) unless Agrammon::DB::User.new(:username($recipient)).exists;

        my %lx      = $!cfg.translations{$language};
        my $model   = $!cfg.app-variant; # model 'SingleSHL';
        my $sent    = Agrammon::DB::Datasets.new(:$user).send(@datasets, $model, $recipient)<sent>;
        my $sender  = $user.username;
        my $subject = $sent == 1 ?? %lx{'new dataset'}[0]  !! %lx{'new dataset'}[1];
        my $format  = $sent == 1 ?? %lx{'dataset sent'}[0] !! %lx{'dataset sent'}[1];
        my $msg     = sprintf $format, @datasets.join(', '), $sender;
        Agrammon::Email.new(
            :to($recipient),
            :from('support@agrammon.ch'),
            :$subject,
            :$msg,
        ).send;
        return %(:$sent);
    }

    method load-dataset(Agrammon::Web::SessionUser $user, Str $name) {
        warn "***** load-dataset($name) not yet completely implemented (branching)";
        my @data = Agrammon::DB::Dataset.new(:$user, :$name).load.data;
        return @data;
    }

    method create-dataset(Agrammon::Web::SessionUser $user, Str $name) {
        my $model = self.cfg.app-variant; # model 'SingleSHL';
        return Agrammon::DB::Dataset.new(:$user, :$name, :$model).create.name;
    }

    method clone-dataset(Agrammon::Web::SessionUser $user,
                         Str $new-username,
                         Str $old-dataset, Str $new-dataset --> Nil) {
        my $model = self.cfg.app-variant; # model 'SingleSHL';
        Agrammon::DB::Dataset.new(:$user, :$model).clone(:$new-username, :$old-dataset, :$new-dataset);
    }

    method rename-dataset(Agrammon::Web::SessionUser $user, Str $old, Str $new --> Nil) {
        Agrammon::DB::Dataset.new(:$user, :name($old)).rename($new);
    }

    method submit-dataset(Agrammon::Web::SessionUser $user, %params) {
        my %lx = $!cfg.translations{%params<language> // 'de'};

        my $recipientKey = %params<recipientKey>;
        my $recipientMail;
        for @($!cfg.submission) -> %s {
            $recipientMail = %s<email> if %s<key> eq $recipientKey;
        }
        die "Recipient for key $recipientKey not found" unless $recipientMail;

        my $old-dataset  = %params<oldDataset>;
        my $new-dataset  = submission-dataset(%params);
        self.clone-dataset($user, $recipientMail, $old-dataset, $new-dataset);
        my $attachment = self.get-pdf-export($user, %params);
        my $subject = %lx<dataset> ~ ": $new-dataset";
        my $format = %lx{'dataset sent'}[0];
        my $msg = sprintf $format, $new-dataset, %params<username>;

        Agrammon::Email.new(
            :to($recipientMail),
            :from('support@agrammon.ch'),
            :$subject,
            :$msg,
            :$attachment,
            :filename($new-dataset.subst(/<-[\w_.-]>/, '', :g) ~ '.pdf')
        ).send;
    }

    method store-dataset-comment(Agrammon::Web::SessionUser $user, Str $name, Str $comment) {
        return Agrammon::DB::Dataset.new(:$user, :$name).store-comment($comment);
    }

    method get-tags(Agrammon::Web::SessionUser $user) {
        return Agrammon::DB::Tags.new(:$user).load.list;
    }

    method create-tag(Agrammon::Web::SessionUser $user, Str $name --> Nil) {
        Agrammon::DB::Tag.new(:$user, :$name).create;
    }

    method delete-tag(Agrammon::Web::SessionUser $user, Str $name --> Nil) {
        Agrammon::DB::Tag.new(:$user, :$name).delete;
    }

    method rename-tag(Agrammon::Web::SessionUser $user, Str $old, Str $new --> Nil) {
        Agrammon::DB::Tag.new(:$user, :name($old)).rename($new);
    }

    method set-tag(Agrammon::Web::SessionUser $user, @datasets, Str $tag-name --> Nil) {
        Agrammon::DB::Dataset.new(:$user).set-tag(@datasets, $tag-name);
    }

    method remove-tag(Agrammon::Web::SessionUser $user, @datasets, Str $tag-name --> Nil) {
        Agrammon::DB::Dataset.new(:$user).remove-tag(@datasets, $tag-name);
    }

    method get-input-variables {
        return $!ui-web.get-input-variables;
    }

    method !get-inputs($user, $dataset-name) {
        Agrammon::DataSource::DB.new.read($user.username, $dataset-name, $!model.distribution-map);
    }

    method !get-outputs(Agrammon::Web::SessionUser $user, Str $dataset-name) {
        return $!outputs-cache.get-or-calculate: $user.username, $dataset-name, -> {
            timed "$dataset-name", {
                $!model.run:
                        :input(self!get-inputs($user, $dataset-name)),
                        technical => %!technical-parameters;
            }
        }
    }

    method get-output-variables(Agrammon::Web::SessionUser $user, Str $dataset-name) {
        my $outputs = self!get-outputs($user, $dataset-name);

        # TODO: get with-filters from frontend
        my %gui-output = output-for-gui($!model, $outputs, :include-filters);
        note '**** with-filters for get-output-variables() not yet completely implemented';
        return %gui-output;
    }

    method get-excel-export(Agrammon::Web::SessionUser $user, %params) {
        my $dataset-name    = %params<datasetName>;
        my $language        = %params<language>;
        my $report-selected = %params<reportSelected>.Int;

        my $inputs  = self!get-inputs($user, $dataset-name);
        my $outputs = self!get-outputs($user, $dataset-name);
        my $reports = self.get-input-variables<reports>;

        my $type = $reports[$report-selected]<type> // '';
        my $with-filters = $type eq 'reportDetailed';
        my $all-filters = $type eq 'reportDetailed';

        input-output-as-excel(
            $!cfg,
            $user,
            $dataset-name,
            $!model, $outputs, $inputs, $reports,
            $language, $report-selected,
            $with-filters, $all-filters
        );
    }

    method get-pdf-export(Agrammon::Web::SessionUser $user, %params) {
        my $dataset-name    = %params<datasetName>;
        my $language        = %params<language>;
        my $report-selected = %params<reportSelected>.Int;

        my %submission;
        if %params<mode> and %params<mode> eq 'submission' {
            my $sender-name = %params<senderName>;
            # replace URL pseudo-encoded newlines from frontend
            $sender-name ~~ s:g/XXX/\\newline\{\}/;
            my $comment = %params<comment>;
            $comment ~~ s:g/XXX/\\newline\{\}/;
            my $dataset-name = submission-dataset(%params);
            %submission =
                :farm-number(%params<farmNumber>),
                :farm-situation(%params<farmSituation>),
                :$comment,
                :$sender-name,
                :recipient-name(%params<recipientName>),
                :recipient-email(%params<recipientEmail>),
                :$dataset-name;
        }

        my $inputs  = self!get-inputs($user, $dataset-name);
        my $outputs = self!get-outputs($user, $dataset-name);
        my $reports = self.get-input-variables<reports>;

        my $type = $reports[$report-selected]<type> // '';
        my $with-filters = $type eq 'reportDetailed';
        my $all-filters  = $type eq 'reportDetailed';

        input-output-as-pdf(
            $!cfg,
            $user,
            $dataset-name,
            $!model, $outputs, $inputs, $reports,
            $language, $report-selected,
            $with-filters, $all-filters, :%submission
       );
    }

    method create-account(Agrammon::Web::SessionUser $user, $email, $password, $key, $firstname, $lastname, $org, $role?) {
        return Agrammon::DB::User.new(
            :username($email), :$password,
            :$firstname, :$lastname,
            :organisation($org)
        ).create-account($role).username;
    }

    method change-password(Agrammon::Web::SessionUser $user, Str $old-password, Str $new-password --> Nil) {
        $user.change-password($old-password, $new-password);
    }

    method reset-password(Agrammon::Web::SessionUser $user, Str $email, Str $password, Str $key) {
        return $user.reset-password($email, $password, $key);
    }

    method store-data(Agrammon::Web::SessionUser $user, $dataset-name, $variable, $value, @branches?, @options?, $row? --> Nil) {
        # TODO: not sure where row is needed; implement branches

        my $ds = Agrammon::DB::Dataset.new(:$user, :name($dataset-name));
        $ds.store-input($variable, $value);

        $!outputs-cache.invalidate($user.username, $dataset-name);

        if $row {
            warn "**** store-data(var=$variable, value=$value, row=$row): what is row used for???";
            dd $row;
        }
        if @branches {
            warn "**** store-data(var=$variable, value=$value): not yet completely implemented (branch data)";
            dd @branches;
            dd @options;
        }
    }

    method store-input-comment(Agrammon::Web::SessionUser $user, $dataset, $variable, $comment --> Nil) {
        Agrammon::DB::Dataset.new(:$user, :name($dataset)).store-input-comment($variable, $comment);
    }

    method delete-instance(Agrammon::Web::SessionUser $user, $dataset-name, $variable-pattern, $instance --> Nil) {
        Agrammon::DB::Dataset.new(:$user, :name($dataset-name)).delete-instance($variable-pattern, $instance);
        $!outputs-cache.invalidate($user.username, $dataset-name);
    }

    method load-branch-data(Agrammon::Web::SessionUser $user, Str $name, %data) {
        return Agrammon::DB::Dataset.new(:$user, :$name).lookup
            .load-branch-data(%data<vars>, %data<instance>);
    }

    method store-branch-data(Agrammon::Web::SessionUser $user, Str $name, %data) {
        return Agrammon::DB::Dataset.new(:$user, :$name).lookup
            .store-branch-data(%data<vars>, %data<instance>, %data<options>, %data<data>);
    }

    method rename-instance(Agrammon::Web::SessionUser $user, Str $dataset-name, Str $old-instance, Str $new-instance, Str $variable-pattern --> Nil) {
        Agrammon::DB::Dataset.new(:$user, :name($dataset-name)).rename-instance($old-instance, $new-instance, $variable-pattern);
    }

    method order-instances(Agrammon::Web::SessionUser $user, Str $dataset-name, @instances) {
        Agrammon::DB::Dataset.new(:$user, :name($dataset-name)).order-instances(@instances);
    }

    sub submission-dataset(%params --> Str) {
        %params<farmNumber>    ~ ', ' ~
                %params<farmSituation> ~ ', ' ~
                %params<username>      ~ ', ' ~
                %params<datasetName>   ~ ', ' ~
                timestamp
    }

}
