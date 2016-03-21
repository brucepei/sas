% my $tb = shift;
<?xml version="1.0" encoding="UTF-8"?>
<testBatch name="<%= $tb->{name} %>" loops="<%= $tb->{loops} ? 'TRUE' : 'FALSE' %>">
% if (ref $tb->{ts}) {
    % foreach my $ts ( @{$tb->{ts}} ) {
    <%= indent $ts->print, '    ' %>
    % }
% }
</testBatch>