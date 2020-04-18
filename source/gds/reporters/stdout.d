module gds.reporters.stdout;

import gds.reporters.reporter : Reporter;
import gds.store;

class Stdout : Reporter
{
    void report(Store[] stores)
    {
        import std.stdio : writeln;

        if (stores.length > 0)
            generateReport(stores).writeln;
    }

private:

    static struct StoreFormatter
    {
        Store store;

        static string formatString()
        {
            import std.array : join;

            string[] fields;

            static foreach (e ; typeof(this).tupleof)
                fields ~= e.stringof ~ ": %s";

            return fields.join("\n");
        }

        string toString()
        {
            import std.format : format;
            import std.algorithm : map, sort;

            auto shippingSlots = store
                .shippingSlots
                .sort!((a, b) => a.date < b.date)
                .map!(s => ShippingSlotFormatter(s));

            return format!"=== %s ===\n%(%s\n\n%)"(store.name, shippingSlots);
        }
    }

    immutable static struct ShippingSlotFormatter
    {
        ShippingSlot shippingSlot;

        static string formatString()
        {
            import std.array : join;

            string[] fields;

            static foreach (e ; ShippingSlot.tupleof)
                fields ~= "    " ~ e.stringof ~ ": %s";

            return fields.join("\n");
        }

        string toString()
        {
            import std.format : format;

            alias formatBool = b => b ? "✔" : "✗";

            return format!(formatString())(
                shippingSlot.id,
                shippingSlot.price,
                shippingSlot.date.toISOExtString,
                shippingSlot.hours,
                shippingSlot.cutOffDate.toISOExtString,
                formatBool(shippingSlot.isExpressSlot),
                formatBool(shippingSlot.isSpecial)
            );
        }
    }

    string generateReport(Store[] stores)
    {
        import std.format : format;
        import std.algorithm : map;

        return format!"%(%s\n\n%)"(stores.map!(s => StoreFormatter(s)));
    }
}

@("generateReport")
unittest
{
    import std.datetime : Date, DateTime;

    enum ShippingSlot shippingSlot1 = {
        id: "ad976334-8e88-4518-ba80-47126633f84d",
        price: "79 kr",
        date: Date(2020, 1, 1),
        hours: "13:00 - 20:00",
        cutOffDate: DateTime(2020, 1, 1, 23, 59, 0),
        isExpressSlot: false,
        isSpecial: true
    };

    enum ShippingSlot shippingSlot2 = {
        id: "16455cf1-d4cd-4d47-86ce-e91b2f7c53eb",
        price: "79 kr",
        date: Date(2020, 1, 2),
        hours: "13:00 - 20:00",
        cutOffDate: DateTime(2020, 1, 3, 23, 59, 0),
        isExpressSlot: false,
        isSpecial: true,
    };

    enum Store store1 = {
        name: "foo",
        shippingSlots: [shippingSlot1, shippingSlot2]
    };

    enum ShippingSlot shippingSlot3 = {
        id: "ad976334-8e88-4518-ba80-47126633f84c",
        price: "79 kr",
        date: Date(2020, 1, 1),
        hours: "13:00 - 20:00",
        cutOffDate: DateTime(2020, 1, 1, 23, 59, 0),
        isExpressSlot: false,
        isSpecial: true
    };

    enum ShippingSlot shippingSlot4 = {
        id: "16455cf1-d4cd-4d47-86ce-e91b2f7c53ed",
        price: "79 kr",
        date: Date(2020, 1, 3),
        hours: "13:00 - 20:00",
        cutOffDate: DateTime(2020, 1, 4, 23, 59, 0),
        isExpressSlot: false,
        isSpecial: true,
    };

    enum Store store2 = {
        name: "bar",
        shippingSlots: [shippingSlot3, shippingSlot4]
    };

    enum stores = [store1, store2];

    enum expected = "=== foo ===
    id: ad976334-8e88-4518-ba80-47126633f84d
    price: 79 kr
    date: 2020-01-01
    hours: 13:00 - 20:00
    cutOffDate: 2020-01-01T23:59:00
    isExpressSlot: ✗
    isSpecial: ✔

    id: 16455cf1-d4cd-4d47-86ce-e91b2f7c53eb
    price: 79 kr
    date: 2020-01-02
    hours: 13:00 - 20:00
    cutOffDate: 2020-01-03T23:59:00
    isExpressSlot: ✗
    isSpecial: ✔

=== bar ===
    id: ad976334-8e88-4518-ba80-47126633f84c
    price: 79 kr
    date: 2020-01-01
    hours: 13:00 - 20:00
    cutOffDate: 2020-01-01T23:59:00
    isExpressSlot: ✗
    isSpecial: ✔

    id: 16455cf1-d4cd-4d47-86ce-e91b2f7c53ed
    price: 79 kr
    date: 2020-01-03
    hours: 13:00 - 20:00
    cutOffDate: 2020-01-04T23:59:00
    isExpressSlot: ✗
    isSpecial: ✔";

    scope stdout = new Stdout;
    assert(stdout.generateReport(stores) == expected);
}

