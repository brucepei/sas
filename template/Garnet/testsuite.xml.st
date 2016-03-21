% my $ts = shift;
<testSuite name="<%= $ts->{name} %>" iterations="<%= $ts->{count} %>" preTestDelay="<%= $ts->{pre_delay} %>" postTestDelay="<%= $ts->{post_delay} %>" shuffled="<%= $ts->{shuffle} ? 'TRUE' : 'FALSE' %>" concurrent="<%= $ts->{concurrent} ? 'TRUE' : 'FALSE' %>" stopOnError="false">
% if (ref $ts->{tc}) {
    % foreach my $tc ( @{$ts->{tc}} ) {
    <%= indent $tc->print, '    ' %>
    % }
% }
</testSuite>