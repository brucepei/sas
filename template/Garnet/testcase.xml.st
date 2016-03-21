% my $tc = shift;
<testCase name="<%= $tc->{name} %>" iterations="<%= $tc->{count} %>" preTestDelay="<%= $tc->{pre_delay} %>" postTestDelay="<%= $tc->{post_delay} %>">
% if (ref $tc->{ta}) {
    % foreach my $ta ( @{$tc->{ta}} ) {
    <%= indent $ta->print, '    ' %>
    % }
% }
</testCase>