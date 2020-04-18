module gds.email_sender;

struct Recipient
{
    string name;
    string address;

    string toString() const pure @safe
    {
        import std.format : format;

        if (name.length > 0)
            return format!`"%s" <%s>`(name, address);
        else
            return format!"<%s>"( address);
    }

    @("with name and address")
    unittest
    {
        enum Recipient recipient = {
            name: "foo",
            address: "foo@bar.com"
        };

        assert(recipient.toString == `"foo" <foo@bar.com>`);
    }

    @("with only address")
    unittest
    {
        enum Recipient recipient = {
            address: "foo@bar.com"
        };

        assert(recipient.toString == `<foo@bar.com>`);
    }
}

struct Message
{
    Recipient to;
    Recipient from;
    string subject;
    string body;

    string toMessageString()
    {
        import std.array : staticArray;
        import std.format : format;

        auto headers = [
            "To: " ~ to.toString,
            "From: " ~ from.toString,
            "Subject: " ~ subject,
            "Content-Type: text/html; charset=UTF-8"
        ].staticArray;

        return format!"%-(%s\r\n%)\r\n\r\n%s\r\n"(headers[], body);
    }

    unittest
    {
        import std.stdio : writeln;
        import std.array : replace;
        import std.string : strip;

        enum Message message = {
            subject: "This is the subject",
            body: "This is the message",
            to: {
                name: "foo",
                address: "foo@mail.com"
            },
            from: {
                name: "bar",
                address: "bar@mail.com"
            }
        };

        enum expected = q"MAIL
To: "foo" <foo@mail.com>
From: "bar" <bar@mail.com>
Subject: This is the subject
Content-Type: text/html; charset=UTF-8

This is the message
MAIL".replace("\n", "\r\n");

        assert(message.toMessageString == expected);
    }
}

struct Authentication
{
    string username;
    string password;
}

struct Server
{
    string address;
    Authentication authentication;
}

void sendEmail(Message message, Server server)
{
    import std.net.curl : SMTP;

    auto smtp = SMTP(server.address);

    with (server.authentication)
        smtp.setAuthentication(username, password);

    smtp.mailTo = message.to.address;
    smtp.mailFrom = message.from.address;
    smtp.message = message.toMessageString;

    smtp.perform();
}
