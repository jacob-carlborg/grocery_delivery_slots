module gds.reporters.email;

import gds.reporters.reporter : Reporter;
import gds.store : Store, SlotId;

class Email : Reporter
{
    import gds.config : EmailReporter;

    private string emailAddress;
    private EmailReporter config;

    this(string emailAddress, EmailReporter config)
    {
        this.emailAddress = emailAddress;
        this.config = config;
    }

    void report(.Store[] stores)
    {
        import std.range : empty;

        import gds.email_sender : sendEmail, Server, Message;

        if (stores.empty)
            return;

        Message message = {
            to: { address: emailAddress },
            from: {
                name: config.sender.name,
                address: config.sender.address
            },

            subject: "Leveranstider",
            body: generateReport(stores)
        };

        Server server = {
            address: config.server.address,
            authentication: {
                username: config.server.username,
                password: config.server.password
            }
        };

        message.sendEmail(server);
    }

private:

    static struct ShippingSlot
    {
        SlotId id;
        string price;
        string hours;
        string cutOffDate;

        string isExpressSlot;
        string isExpressSlotColor;

        string isSpecial;
        string isSpecialColor;
    }

    static struct Date
    {
        string date;
        ShippingSlot[] shippingSlots;
    }

    static struct Store
    {
        string name;
        Date[] dates;
    }

    static struct Context
    {
        Store[] stores;
    }

    string generateReport(.Store[] stores)
    {
        import gds.template_renderer : render;

        enum content = import("main.html");
        auto context = buildContext(stores);

        return render(content, context);
    }

    Context buildContext(.Store[] stores)
    {
        import std.algorithm : chunkBy, map, sort;
        import std.array : array;
        import std.range : front;

        alias toColor = value => value ? "green" : "#eb1f07";
        alias toSymbol = value => value ? "✓" : "✗";

        alias toSlot = (slot) {
            ShippingSlot newSlot;

            with (newSlot)
            {
                id = slot.id;
                price = slot.price;
                hours = slot.hours;
                cutOffDate = slot.cutOffDate.toISOExtString;

                isExpressSlot = toSymbol(slot.isExpressSlot);
                isExpressSlotColor = toColor(slot.isExpressSlot);

                isSpecial = toSymbol(slot.isSpecial);
                isSpecialColor = toColor(slot.isSpecial);
            }

            return newSlot;
        };

        alias toSlots = slots =>
            slots
            .map!toSlot
            .array;

        alias toDates = store =>
            store
            .shippingSlots
            .sort!((a, b) => a.date < b.date)
            .chunkBy!((a, b) => a.date == b.date)
            .map!(slots => Date(slots.front.date.toISOExtString, toSlots(slots)))
            .array;

        auto newStores = stores
            .map!(store => Store(store.name, toDates(store)))
            .array;

        return Context(newStores);
    }
}

@("buildContext")
unittest
{
    import std.datetime : Date, DateTime;

    import gds.config : EmailReporter;
    import gds.store : Store, ShippingSlot;

    enum ShippingSlot slot1 = {
        id: "foo1",
        price: "991",
        date: Date(2020, 1, 1),
        hours: "10:00 - 12:00",
        cutOffDate: DateTime(2020, 1, 1, 0, 0, 0),
        isExpressSlot: false,
        isSpecial: true
    };

    enum ShippingSlot slot2 = {
        id: "foo2",
        price: "992",
        date: Date(2020, 1, 2),
        hours: "16:00 - 18:00",
        cutOffDate: DateTime(2020, 1, 1, 0, 0, 0),
        isExpressSlot: false,
        isSpecial: true
    };

    enum ShippingSlot slot3 = {
        id: "foo3",
        price: "992",
        date: Date(2020, 1, 1),
        hours: "18:00 - 20:00",
        cutOffDate: DateTime(2020, 1, 1, 0, 0, 0),
        isExpressSlot: false,
        isSpecial: true
    };

    enum Store store = {
        name: "bar",
        shippingSlots: [slot1, slot2, slot3]
    };

    enum Email.Context expected = {
        stores: [{
            name: store.name,
            dates: [{
                date: slot1.date.toISOExtString,
                shippingSlots: [{
                    id: slot1.id,
                    price: slot1.price,
                    hours: slot1.hours,
                    cutOffDate: slot1.cutOffDate.toISOExtString,
                    isExpressSlot: "✗",
                    isExpressSlotColor: "#eb1f07",
                    isSpecial: "✓",
                    isSpecialColor: "green"
                },
                {
                    id: slot3.id,
                    price: slot3.price,
                    hours: slot3.hours,
                    cutOffDate: slot3.cutOffDate.toISOExtString,
                    isExpressSlot: "✗",
                    isExpressSlotColor: "#eb1f07",
                    isSpecial: "✓",
                    isSpecialColor: "green"
                }]
            },
            {
                date: slot2.date.toISOExtString,
                shippingSlots: [{
                    id: slot2.id,
                    price: slot2.price,
                    hours: slot2.hours,
                    cutOffDate: slot2.cutOffDate.toISOExtString,
                    isExpressSlot: "✗",
                    isExpressSlotColor: "#eb1f07",
                    isSpecial: "✓",
                    isSpecialColor: "green"
                }]
            }]
        }]
    };

    scope email = new Email(null, EmailReporter());
    auto result = email.buildContext([store]);

    assert(result == expected);
}

// unittest
// {
//     import std.datetime : Date, DateTime;
//     import gds.store : Store, ShippingSlot;
//
//     enum ShippingSlot slot = {
//         id: "foo",
//         price: "99",
//         date: Date(2020, 1, 1),
//         hours: "10:00 - 12:00",
//         cutOffDate: DateTime(2020, 1, 1, 0, 0, 0),
//         isExpressSlot: false,
//         isSpecial: true
//     };
//
//     enum Store store1 = {
//         name: "bar",
//         shippingSlots: [{
//             id: "foo",
//             price: "99",
//             date: Date(2020, 1, 1),
//             hours: "10:00 - 12:00",
//             cutOffDate: DateTime(2020, 1, 1, 0, 0, 0),
//             isExpressSlot: false,
//             isSpecial: true
//         },
//         {
//             id: "asd",
//             price: "200",
//             date: Date(2020, 1, 1),
//             hours: "14:00 - 16:00",
//             cutOffDate: DateTime(2020, 1, 1, 0, 0, 0),
//             isExpressSlot: true,
//             isSpecial: false
//         },
//         {
//             id: "asd",
//             price: "200",
//             date: Date(2020, 1, 2),
//             hours: "14:00 - 16:00",
//             cutOffDate: DateTime(2020, 1, 2, 0, 0, 0),
//             isExpressSlot: true,
//             isSpecial: false
//         }]
//     };
//
//     enum Store store2 = {
//         name: "bar2",
//         shippingSlots: [{
//             id: "foo2",
//             price: "99",
//             date: Date(2020, 1, 1),
//             hours: "10:00 - 12:00",
//             cutOffDate: DateTime(2020, 1, 1, 0, 0, 0),
//             isExpressSlot: false,
//             isSpecial: true
//         },
//         {
//             id: "asd2",
//             price: "200",
//             date: Date(2020, 1, 1),
//             hours: "14:00 - 16:00",
//             cutOffDate: DateTime(2020, 1, 1, 0, 0, 0),
//             isExpressSlot: true,
//             isSpecial: false
//         }]
//     };
//
//     scope email = new Email;
//     const result = email.generateReport([store1, store2]);
//     import std.file : write;
//     write("result.html", result);
// }
