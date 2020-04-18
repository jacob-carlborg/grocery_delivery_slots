module gds.config;

struct Sender
{
    string address;
    string name;
}

struct Server
{
    string address;
    string username;
    string password;
}

struct EmailReporter
{
    Sender sender;
    Server server;
}

struct Account
{
    int zip;
    int days;
    bool special;
}

immutable struct Config
{
    EmailReporter emailReporter;
    Account[string] accounts;
}

Config parseConfig(string data)
{
    import std.algorithm : map;
    import std.array : array, assocArray;
    import std.exception : assumeUnique;
    import std.typecons : tuple;

    import dyaml.loader : Loader;
    import dyaml.node : Node;

    static Account toAccount(Node node)
    {
        Account account;

        static foreach (i, field; Account.tupleof)
            account.tupleof[i] = node[field.stringof].as!(typeof(field));

        return account;
    }

    EmailReporter emailReporter;

    auto root = Loader.fromString(data).load;

    if (auto nodePtr = "email_reporter" in root)
    {
        auto node = *nodePtr;

        static foreach (i, field; EmailReporter.tupleof)
        {
            static foreach (j, innerFied; typeof(EmailReporter.tupleof[i]).tupleof)
                emailReporter.tupleof[i].tupleof[j] = node[field.stringof][innerFied.stringof].as!(typeof(innerFied));
        }
    }

    auto accounts = root["accounts"]
        .mapping
        .map!(pair => tuple(pair.key.as!string, toAccount(pair.value)))
        .assocArray;

    Config config = {
        emailReporter: emailReporter,
        accounts: accounts.assumeUnique
    };

    return config;
}

@(`Config with only "accounts"`)
unittest
{
    import std.format : format;

    enum email = "foo@bar.com";
    enum zip = 12345;
    enum days = 7;
    enum special = false;

    enum yaml = q"YAML
accounts:
  %s:
    zip: %s
    days: %s
    special: %s
YAML".format(email, zip, days, special);

    enum Account account = {
        zip: zip,
        days: days,
        special: special
    };

    enum Config expected = {
        accounts: [
            email: account
        ]
    };

    assert(parseConfig(yaml) == expected);
}

@(`Config with "accounts" and "email_reporter"`)
unittest
{
    import std.format : format;

    enum EmailReporter emailReporter = {
        sender: {
            address: "foo@mail.com",
            name: "foo"
        },
        server: {
            address: "smtps://smtp.mail.com",
            username: "foo",
            password: "foobar"
        }
    };

    enum email = "bar@mail.com";
    enum zip = 12345;
    enum days = 7;
    enum special = false;

    enum yaml = q"YAML
email_reporter:
  sender:
    address: %s
    name: %s

  server:
    address: %s
    username: %s
    password: %s

accounts:
  %s:
    zip: %s
    days: %s
    special: %s
YAML".format(
        emailReporter.sender.address,
        emailReporter.sender.name,
        emailReporter.server.address,
        emailReporter.server.username,
        emailReporter.server.password,
        email, zip, days, special);

    enum Account account = {
        zip: zip,
        days: days,
        special: special
    };

    enum Config expected = {
        accounts: [
            email: account
        ],

        emailReporter: emailReporter
    };

    assert(parseConfig(yaml) == expected);
}
