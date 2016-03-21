% my $tc = shift;
<testCase name="<%= $tc->{name} %>" iterations="<%= $tc->{count} || 0 %>" preTestDelay="<%= $tc->{pre_delay} || 0 %>" postTestDelay="<%= $tc->{post_delay} || 0 %>">
% if (ref $tc->{ta}) {
    % foreach my $ta ( @{$tc->{ta}} ) {
    <%= indent $ta->print, '    ' %>
    % }
% }
</testCase>