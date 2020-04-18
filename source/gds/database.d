module gds.database;

import std.conv : to;
import std.datetime : Date, DateTime, SysTime;

import gds.core.set;
import gds.store;

struct ShippingSlotEntry
{
    string account;
    SlotId id;
    Date date;
}

struct Database
{
    private alias ShippingSlots = Date[SlotId];
    private ShippingSlots[string] accounts;

    static Database loadFromDisk(string path)
    {
        import std.file : exists, readText;

        return path.exists ? load(path.readText) : Database();
    }

    static Database load(string data)
    {
        import std.algorithm : map;
        import std.array : array, assocArray;
        import std.exception : assumeUnique;
        import std.typecons : tuple;

        import dyaml.loader : Loader;
        import dyaml.node : Node;

        static ShippingSlots toShippingSlots(Node node)
        {
            alias toShippingSlots = pair =>
                tuple(pair.key.as!string, pair.value.as!SysTime.to!Date);

            return node
                .mapping
                .map!toShippingSlots
                .assocArray;
        }

        auto accounts = Loader
            .fromString(data)
            .load["accounts"]
            .mapping
            .map!(pair => tuple(pair.key.as!string, toShippingSlots(pair.value)))
            .assocArray;

        return Database(accounts);
    }

    void saveToDisk(string path)
    {
        import std.file : write;
        write(path, save);
    }

    string save()
    {
        import std.algorithm : each, sort;
        import std.array : appender, array;
        import std.conv : to;
        import std.datetime : SysTime;
        import std.range : empty;

        import dyaml : CollectionStyle, dyamlDumper = dumper, Node;

        auto buffer = appender!string;
        auto accounts = Node();

        alias accountsNode = () =>
            this.accounts.empty ? Node(string[string].init) : accounts;

        foreach (account, slots; this.accounts)
        {
            if (slots.empty)
                continue;

            auto node = Node();

            slots
                .byKeyValue
                .array
                .sort!((a, b) => a.value < b.value)
                .each!(kv => node.add(kv.key, kv.value.to!SysTime));

            accounts.add(account, node);
        }

        auto root = Node(["accounts": accountsNode()]);

        auto dumper = dyamlDumper;
        dumper.defaultCollectionStyle = CollectionStyle.block;
        dumper.YAMLVersion = null;
        dumper.dump(buffer, root);

        return buffer.data;
    }

    Set!SlotId slotIds(string account)
    {
        import std.algorithm : each;

        Set!SlotId set;

        if (auto a = account in accounts)
            a.byKey.each!(key => set.put(key));

        return set;
    }

    void add(ShippingSlotEntry entry)
    {
        with (entry)
            accounts[account][id] = date;
    }

    void remove(ShippingSlotEntry entry)
    {
        with (entry)
            if (auto a = account in accounts)
                (*a).remove(id);
    }

    void removeExpiredEntries(Date date)
    {
        import std.algorithm : each, filter, map;
        import std.array : array, assocArray;
        import std.range : empty, walkLength;
        import std.stdio : writeln;
        import std.typecons : tuple;

        import gds.core.algorithm : flatMap;

        alias shippingSlotsOlderThan = (account, shippingSlots) =>
            shippingSlots
                .byKeyValue
                .filter!(kv => kv.value <= date)
                .map!(e => tuple(account, e.key));

        auto entriesToRemove = accounts
            .byKeyValue
            .flatMap!(kv => shippingSlotsOlderThan(kv.key, kv.value))
            .array;

        entriesToRemove
            .each!(t => accounts[t[0]].remove(t[1]));

        auto accountsToRemove = accounts
            .byKeyValue
            .filter!(kv => kv.value.empty)
            .map!(kv => kv.key)
            .array;

        accountsToRemove.each!(key => accounts.remove(key));
    }
}

@("load")
unittest
{
    import std.format : format;
    import std.stdio : writeln;
    import std.datetime : TimeOfDay;

    enum email = "foo@bar.com";
    enum id = "4f51d4b2-c84e-4669-99ea-72a46e63c3a2";
    enum timeOfDay = TimeOfDay(0, 0, 0);
    enum date = Date(2020, 1, 2);
    enum dateTime = DateTime(date, timeOfDay).toISOExtString;

    enum yaml = q"YAML
accounts:
  %s:
    %s: %s
YAML".format(email, id, dateTime);

    enum dates = [id: date];

    enum Database expected = {
        accounts: [
            email: dates
        ]
    };

    assert(Database.load(yaml) == expected);
}

@("slotIds")
{
    @("when account exists")
    unittest
    {
        enum id1 = "4f51d4b2-c84e-4669-99ea-72a46e63c3a1";
        enum id2 = "4f51d4b2-c84e-4669-99ea-72a46e63c3a2";

        static immutable ShippingSlotEntry entry1 = {
            account: "one@bar.com",
            id: id1,
            date: Date(2020, 1, 1)
        };

        static immutable ShippingSlotEntry entry2 = {
            account: entry1.account,
            id: id2,
            date: Date(2020, 1, 2)
        };

        enum shippingSlots = [entry1.id: entry1.date, entry2.id: entry2.date];

        Database database = {
            accounts: [
                entry1.account: shippingSlots
            ]
        };

        const result = database.slotIds(entry1.account);

        assert(id1 in result);
        assert(id2 in result);
    }

    @("when account does not exist")
    unittest
    {
        assert(Database().slotIds("foobar")[].empty);
    }
}

@("Add entry when account doesn't exist")
unittest
{
    static immutable ShippingSlotEntry entry = {
        account: "foo@bar.com",
        id: "4f51d4b2-c84e-4669-99ea-72a46e63c3a1",
        date: Date(2020, 1, 1)
    };

    enum shippingSlots = [entry.id: entry.date];

    enum Database expected = {
        accounts: [
            entry.account: shippingSlots
        ]
    };

    Database database;
    database.add(entry);

    assert(database == expected);
}

@("Add entry when account does exist")
unittest
{
    static immutable ShippingSlotEntry entry1 = {
        account: "one@bar.com",
        id: "4f51d4b2-c84e-4669-99ea-72a46e63c3a1",
        date: Date(2020, 1, 1)
    };

    static immutable ShippingSlotEntry entry2 = {
        account: entry1.account,
        id: "4f51d4b2-c84e-4669-99ea-72a46e63c3a2",
        date: Date(2020, 1, 2)
    };

    enum expectedShippingSlots = [
        entry1.id: entry1.date,
        entry2.id: entry2.date
    ];

    enum Database expected = {
        accounts: [
            entry1.account: expectedShippingSlots
        ]
    };

    enum shippingSlots = [entry1.id: entry1.date];

    Database database = {
        accounts: [
            entry1.account: shippingSlots
        ]
    };

    database.add(entry2);

    assert(database == expected);
}

@("Remove existing shipping slot")
unittest
{
    enum email1 = "one@bar.com";
    enum id1 = "4f51d4b2-c84e-4669-99ea-72a46e63c3a1";
    enum date1 = Date(2020, 1, 1);
    enum id2 = "4f51d4b2-c84e-4669-99ea-72a46e63c3a2";
    enum date2 = Date(2020, 1, 2);
    enum shippingSlots1 = [id1: date1, id2: date2];

    enum email2 = "two@bar.com";
    enum id3 = "4f51d4b2-c84e-4669-99ea-72a46e63c3a3";
    enum date3 = Date(2020, 1, 3);
    enum id4 = "4f51d4b2-c84e-4669-99ea-72a46e63c3a4";
    enum date4 = Date(2020, 1, 4);
    enum shippingSlots2 = [id3: date3, id4: date4];


    Database datebase = {
        accounts: [
            email1: shippingSlots1,
            email2: shippingSlots2
        ]
    };

    enum expectedEmail2 = [id3: date3];

    enum Database expected = {
        accounts: [
            email1: shippingSlots1,
            email2: expectedEmail2
        ]
    };

    enum ShippingSlotEntry entry = {
        account: email2,
        id: id4
    };

    datebase.remove(entry);

    assert(datebase == expected);
}

@("Remove non-existing shipping slot")
unittest
{
    enum shippingSlots = [
        "4f51d4b2-c84e-4669-99ea-72a46e63c3a1": Date(2020, 1, 1),
        "4f51d4b2-c84e-4669-99ea-72a46e63c3a2": Date(2020, 1, 2)
    ];

    enum Database expected = {
        accounts: [
            "one@bar.com": shippingSlots
        ]
    };

    Database datebase = expected;

    enum ShippingSlotEntry entry = {
        account: "foo",
        id: "bar"
    };

    datebase.remove(entry);

    assert(datebase == expected);
}

@("Remove expired entries")
unittest
{
    static immutable ShippingSlotEntry entry1 = {
        account: "foo@bar.com",
        id: "4f51d4b2-c84e-4669-99ea-72a46e63c3a1",
        date: Date(2020, 1, 1)
    };

    static immutable ShippingSlotEntry entry2 = {
        account: "foo@bar.com",
        id: "4f51d4b2-c84e-4669-99ea-72a46e63c3a2",
        date: Date(2020, 1, 2)
    };

    enum shippingSlots = [
        entry1.id: entry1.date,
        entry2.id: entry2.date
    ];

    Database database = {
        accounts: [
            entry1.account: shippingSlots
        ]
    };

    enum expectedShippingSlots = [entry2.id: entry2.date];

    enum Database expected = {
        accounts: [
            entry2.account: expectedShippingSlots
        ]
    };

    database.removeExpiredEntries(entry1.date);
    assert(database == expected);
}

@("Remove expired entries causing account to be removed")
unittest
{
    import std.datetime : days;

    static immutable ShippingSlotEntry entry1 = {
        account: "foo@bar.com",
        id: "4f51d4b2-c84e-4669-99ea-72a46e63c3a1",
        date: Date(2020, 1, 1)
    };

    static immutable ShippingSlotEntry entry2 = {
        account: "foo@bar.com",
        id: "4f51d4b2-c84e-4669-99ea-72a46e63c3a2",
        date: Date(2020, 1, 2)
    };

    enum shippingSlots = [
        entry1.id: entry1.date,
        entry2.id: entry2.date
    ];

    Database database = {
        accounts: [
            entry1.account: shippingSlots
        ]
    };

    enum expected = Database();

    database.removeExpiredEntries(entry2.date + 2.days);
    assert(database == expected);
}

@("save")
{
    @("when database is not empty")
    unittest
    {
        import std.datetime : Date, DateTime, TimeOfDay;
        import std.format : format;

        enum timeOfDay = TimeOfDay(0, 0, 0);

        enum date1 = Date(2020, 1, 1);
        enum dateTime1 = DateTime(date1, timeOfDay).toISOExtString;

        enum date2 = Date(2020, 1, 2);
        enum dateTime2 = DateTime(date2, timeOfDay).toISOExtString;

        static immutable ShippingSlotEntry entry1 = {
            account: "foo@bar.com",
            id: "4f51d4b2-c84e-4669-99ea-72a46e63c3a1",
            date: date1
        };

        static immutable ShippingSlotEntry entry2 = {
            account: "foo@bar.com",
            id: "4f51d4b2-c84e-4669-99ea-72a46e63c3a2",
            date: date2
        };

        enum shippingSlots = [
            entry1.id: entry1.date,
            entry2.id: entry2.date
        ];

        Database database = {
            accounts: [
                entry1.account: shippingSlots
            ]
        };

        enum expected = q"YAML
accounts:
  %s:
    %s: %s
    %s: %s
YAML".format(entry1.account,
        entry1.id, dateTime1,
        entry2.id, dateTime2,
      );

        assert(database.save == expected);
    }

    @("when database is empty")
    unittest
    {
        enum expected = q"YAML
accounts: {}
YAML";

        assert(Database().save == expected);
    }
}
