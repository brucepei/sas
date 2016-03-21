% my $ts = shift;
<testSuite name="<%= $ts->{name} %>" iterations="<%= $ts->{count} || 0 %>" preTestDelay="<%= $ts->{pre_delay} || 0 %>" postTestDelay="<%= $ts->{post_delay} || 0 %>" shuffled="<%= $ts->{shuffle} ? 'TRUE' : 'FALSE' %>" concurrent="<%= $ts->{concurrent} ? 'TRUE' : 'FALSE' %>" stopOnError="false">
% if (ref $ts->{tc}) {
    % foreach my $tc ( @{$ts->{tc}} ) {
    <%= indent $tc->print, '    ' %>
    % }
% }
</testSuite>