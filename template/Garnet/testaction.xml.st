% my $ta = shift;
<test action="<%= $ta->{name} %>" iterations="<%= $ta->{count} %>" duration="<%= $ta->{time} %>" preTestDelay="<%= $ta->{pre_delay} %>" postTestDelay="<%= $ta->{post_delay} %>">
    % if (ref $ta->{para}) {
    <config>
        % foreach my $i (1..@{$ta->{para}}) {
        <property name="<%= $ta->para($i) || '' %>" value="<%= $ta->val($i) || '' %>" />
        % }
    </config>
    % }
</test>