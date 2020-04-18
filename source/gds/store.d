module gds.store;

import std.datetime : Date, DateTime;

alias SlotId = string;

struct Store
{
    string name;

    ShippingSlot[] shippingSlots;
}

struct ShippingSlot
{
    SlotId id;
    string price;

    Date date;
    string hours;
    DateTime cutOffDate;

    bool isExpressSlot;
    bool isSpecial;

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

        return this.tupleof.format!(formatString());
    }
}
