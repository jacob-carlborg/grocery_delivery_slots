module gds.stores.ica;

import core.thread : Thread;

import std;

import asdf;

import gds.core.algorithm;
import gds.core.set;
import gds.store;
import gds.utility;

version = Thread;

version (Thread)
{
    static class StoreThread : Thread
    {
        this(size_t index, Ica.Store store, void delegate(size_t, Ica.Store) block)
        {
            super({ block(index, store); });
        }
    }
}

class Ica
{
    private int zipCode;

    this(int zipCode)
    {
        this.zipCode = zipCode;
    }

    .Store[] availableShippingSlotsWithin(Duration duration,
        bool includeSpecial, Set!SlotId slotsToExclude)
    {
        auto stores = parseStores(fetchStoresData);

        return availableShippingSlotsWithinImpl!fetchAllShippingSlotsWithin(
            stores, duration, includeSpecial, slotsToExclude
        );
    }

private:

    static struct Store
    {
        string id;
        string name;
        @serializationIgnore void delegate(const ref Store) block;

        void apply()
        {
            block(this);
        }
    }

    static struct Availability
    {
        string id;
        string name;
        string hours;
        bool isAvailable;
        string price;
        @serializedAs!DateTimeProxy DateTime cutOffDate;
        bool isStandardCutOff;
        bool isExpressSlot;
        bool isCutOffToday;
        @serializationIgnore bool isSpecial;

        static string formatString()
        {
            string[] fields;

            static foreach (e ; typeof(this).tupleof)
                fields ~= e.stringof ~ ": %s";

            return fields.join("\n");
        }

        void finalizeDeserialization(Asdf)
        {
            enum specialSuffix = " SPECIAL1*";
            isSpecial = name.endsWith(specialSuffix);
            name = name.chomp(specialSuffix);
        }

        string toString()
        {
            return this.tupleof.format!(formatString());
        }
    }

    static struct Date
    {
        @serializedAs!DateProxy .Date date;
        Availability[] availability;
    }

    static struct ShippingSlots
    {
        @serializedAs!string int week;
        @serializedAs!string int weekPrev;
        @serializedAs!string int weekNext;

        int currentWeekIndex;
        int weekPrevIndex;
        @serializationFlexible int weekNextIndex;

        Date[] dates;
    }

    static struct DateTimeProxy
    {
        DateTime datetime;
        alias datetime this;

        static DateTimeProxy deserialize(Asdf data)
        {
            string value;
            deserializeScopedString(data, value);
            return DateTimeProxy(toDateTime(value));
        }

        private static DateTime toDateTime(string value)
        {
            const newValue = value.split(".").front.replace(" ", "T");
            return DateTime.fromISOExtString(newValue);
        }

        unittest
        {
            enum expected = DateTime(2020, 4, 12, 12, 0, 0);
            enum result = DateTimeProxy.toDateTime("2020-04-12 12:00:00.0");

            assert(result == expected);
        }
    }

    static struct DateProxy
    {
        .Date date;
        alias date this;

        static DateProxy deserialize(Asdf data)
        {
            string value;
            deserializeScopedString(data, value);

            return DateProxy(toDate(value));
        }

        static .Date toDate(string value)
        {
            const components = value.splitter("/").map!(to!int).array;
            const currentDate = Clock.currTime.to!(.Date);

            return .Date(currentDate.year, components[1], components[0]);
        }

        unittest
        {
            enum expected = .Date(2020, 4, 13);
            const result = DateProxy.toDate("13/4");

            assert(result == expected);
        }
    }

    .Store[] availableShippingSlotsWithinImpl
        (alias fetchAllShippingSlotsWithin)
        (Store[] stores, Duration duration, bool includeSpecial,
            Set!SlotId slotsToExclude)
    {
        import core.thread : Thread;

        alias availabilityToShippingSlot = (date, a) =>
            ShippingSlot(a.id, a.price, date, a.hours.replace("\n", ""),
                a.cutOffDate, a.isExpressSlot, a.isSpecial);

        alias toShippingSlot = slots =>
            slots.dates.flatMap!(date =>
                date
                .availability
                .filter!(a => a.isAvailable)
                .filter!(a => includeSpecial ? true : !a.isSpecial)
                .filter!(a => a.id !in slotsToExclude)
                .map!(a => availabilityToShippingSlot(date.date, a))
            );

        alias shippingSlots = store =>
            fetchAllShippingSlotsWithin(duration, store.id)
            .flatMap!toShippingSlot
            .array;

        alias toCommonStore = icaStore =>
            .Store(icaStore.name, shippingSlots(icaStore));

        version (Thread)
        {
            .Store[] newStores = new .Store[stores.length];

            StoreThread[] threads;
            threads.reserve(stores.length);

            foreach (index, ref store; stores)
            {
                threads ~= new StoreThread(index, store, (i, s) {
                    auto newStore = toCommonStore(s);

                    if (!newStore.shippingSlots.empty)
                        newStores[i] = newStore;
                });

                threads[$ - 1].start();
            }

            threads.each!(thread => thread.join);

            return newStores
                .filter!(store => !store.shippingSlots.empty)
                .array;
        }

        else
        {
            return stores
                .map!toCommonStore
                .filter!(store => !store.shippingSlots.empty)
                .array;
        }
    }

    ShippingSlots parseShippingSlots(string data)
    {
        return data.deserialize!ShippingSlots;
    }

    Store[] parseStores(string data)
    {
        static struct Reponse
        {
            Store[] forHomeDelivery;
        }

        return data
            .deserialize!Reponse
            .forHomeDelivery
            .take(10)
            .array;
    }

    string fetchStoresData()
    out(result)
    {
        // writefln!"fetchStoresData result:\n%s"(result);
    }
    do
    {
        const url = format!"https://handla.ica.se/api/store/v1?zip=%s&customerType=B2C"(zipCode);
        return get(url).assumeUnique;

        // return readText("fetchStores.json");
    }

    string fetchShippingData(string storeId, int weekIndex)
    in
    {
        // writefln!"fetchShippingData.in storeId=%s, weekIndex=%s"(storeId, weekIndex);
    }
    out(result)
    {
        // writefln!"fetchShippingData.out storeId=%s weekIndex=%s result:\n%s"(storeId, weekIndex, result);
    }
    do
    {
        enum SlotType
        {
            pickupInStore = 1,
            homeDelivery = 2
        }

        const url = format!"https://www.ica.se/handla/cart/frags/getShippingSlots.jsp?slotType=%d&postCode=%s&weekIndex=%s"(SlotType.homeDelivery, zipCode, weekIndex);
        const cookies = format!`CC_%s={"orderId":"0","siteId":"800004","accessedTime":1586182968133,"recipes":[],"itemList":[]}`(storeId);
        auto http = HTTP(url);
        http.setCookie(cookies);
        return get(url, http).assumeUnique;

        // return readText("fetchShippingSlots.json");
    }

    ShippingSlots[] fetchAllShippingSlotsWithin(Duration duration, string storeId)
    {
        ShippingSlots currentSlots = { weekNextIndex: 0 };
        ShippingSlots[] shippingSlots;

        immutable  currentDate = .currentDate;

        while(currentSlots.weekNextIndex != -1 &&
            !currentSlots.dates.outsideDuration(duration, currentDate))
        {
            const data = fetchShippingData(storeId, currentSlots.weekNextIndex);
            shippingSlots ~= currentSlots = parseShippingSlots(data);
        }

        return shippingSlots;
    }
}

private:

bool outsideDuration(Ica.Date[] dates, Duration duration,
    Date currentDate = .currentDate)
{
    return dates.any!(date => date.date > currentDate + duration);
}

@("dates outside duration")
unittest
{
    enum dates = [
        Date(2020, 1, 5),
        Date(2020, 1, 6),
        Date(2020, 1, 7)
    ].map!(date => Ica.Date(date)).array;

    enum currentDate = Date(2020, 1, 4);

    assert(dates.outsideDuration(2.days, currentDate));
}

@("no dates outside duration")
unittest
{
    enum dates = [
        Date(2020, 1, 5),
        Date(2020, 1, 6),
        Date(2020, 1, 7)
    ].map!(date => Ica.Date(date)).array;

    enum currentDate = Date(2020, 1, 4);

    assert(!dates.outsideDuration(3.days, currentDate));
}

@("availableShippingSlotsWithin")
{
    @("when a shipping slot is available")
    unittest
    {
        enum Ica.Store store = { name: "bar" };

        enum Ica.Availability availability = {
            id: "4206d4ce-c61d-4985-9d7e-a5ddaf471237",
            name: "MÃ¥n 1 Privat A",
            hours: "07:00 - 09:00",
            isAvailable: true,
            price: "99 kr",
            cutOffDate: DateTime(2020, 1, 1, 0, 0, 0),
            isStandardCutOff: false,
            isExpressSlot: false,
            isCutOffToday: false,
            isSpecial: false
        };

        enum Ica.Date date = {
            date: Date(2020, 1, 2),
            availability: [availability]
        };

        alias fetchAllShippingSlotsWithin = (duration, storeId) {
            enum Ica.ShippingSlots slot = {
                dates: [date]
            };

            return [slot];
        };


        scope ica = new Ica(12345);
        const result = ica.availableShippingSlotsWithinImpl!fetchAllShippingSlotsWithin(
            [store], 7.days, false, Set!SlotId()
        );

        enum Store expected = {
            name: store.name,
            shippingSlots: [{
                id: availability.id,
                price: availability.price,
                date: date.date,
                hours: availability.hours,
                cutOffDate: availability.cutOffDate,
                isExpressSlot: availability.isExpressSlot,
                isSpecial: availability.isSpecial
            }]
        };

        assert(result.front == expected);
    }

    @("when a shipping slot is not available")
    unittest
    {
        enum Ica.Store store = { name: "bar" };
        enum Ica.Availability availability = { isAvailable: false };
        enum Ica.Date date = { availability: [availability] };

        alias fetchAllShippingSlotsWithin = (duration, storeId) {
            enum Ica.ShippingSlots slot = { dates: [date] };
            return [slot];
        };

        scope ica = new Ica(12345);
        const result = ica.availableShippingSlotsWithinImpl!fetchAllShippingSlotsWithin(
            [store], 7.days, false, Set!SlotId()
        );

        assert(result.empty);
    }

    @("when a shipping slot is special and not including special")
    unittest
    {
        enum Ica.Store store = { name: "bar" };

        enum Ica.Availability availability = {
            isAvailable: true,
            isSpecial: true
        };

        enum Ica.Date date = { availability: [availability] };

        alias fetchAllShippingSlotsWithin = (duration, storeId) {
            enum Ica.ShippingSlots slot = { dates: [date] };
            return [slot];
        };

        scope ica = new Ica(12345);
        const result = ica.availableShippingSlotsWithinImpl!fetchAllShippingSlotsWithin(
            [store], 7.days, false, Set!SlotId()
        );

        assert(result.empty);
    }

    @("when a shipping slot is special and including special")
    unittest
    {
        enum Ica.Store store = { name: "bar" };

        enum Ica.Availability availability = {
            isAvailable: true,
            isSpecial: true
        };

        enum Ica.Date date = { availability: [availability] };

        alias fetchAllShippingSlotsWithin = (duration, storeId) {
            enum Ica.ShippingSlots slot = { dates: [date] };
            return [slot];
        };

        scope ica = new Ica(12345);
        const result = ica.availableShippingSlotsWithinImpl!fetchAllShippingSlotsWithin(
            [store], 7.days, true, Set!SlotId()
        );

        assert(!result.empty);
    }

    @("when there are no shipping slots within the given duration")
    unittest
    {
        enum Ica.Store store = { name: "bar" };
        enum Ica.Availability availability = { isAvailable: true };
        enum Ica.Date date = { availability: [availability] };

        alias fetchAllShippingSlotsWithin = (duration, storeId) =>
            Ica.ShippingSlots[].init;

        scope ica = new Ica(12345);
        const result = ica.availableShippingSlotsWithinImpl!fetchAllShippingSlotsWithin(
            [store], 7.days, false, Set!SlotId()
        );

        assert(result.empty);
    }

    @("when a shipping slot is available")
    unittest
    {
        enum Ica.Store store = { name: "bar" };
        enum id = "4206d4ce-c61d-4985-9d7e-a5ddaf471237";

        enum Ica.Availability availability = {
            id: id,
            isAvailable: true
        };

        enum Ica.Date date = { availability: [availability] };

        alias fetchAllShippingSlotsWithin = (duration, storeId) {
            enum Ica.ShippingSlots slot = { dates: [date] };
            return [slot];
        };


        scope ica = new Ica(12345);
        const result = ica.availableShippingSlotsWithinImpl!fetchAllShippingSlotsWithin(
            [store], 7.days, false, Set!SlotId(id)
        );

        assert(result.empty);
    }
}

@("parseShippingSlots")
unittest
{
    struct JsonValues
    {
        auto week = 16;
        auto weekPrev = 15;
        auto weekNext = 17;

        auto currentWeekIndex = 1;
        auto weekPrevIndex = 0;
        auto weekNextIndex = 2;

        auto date = "13/4";

        auto id = "4206d4ce-c61d-4985-9d7e-a5ddaf471237";
        auto name = "MÃ¥n 1 Privat A";
        auto hours = `07:00\n - 09:00`;
        auto isAvailable = false;
        auto price = "99 kr";
        auto cutOffDate = "2020-04-12 12:00:00.0";
        auto isStandardCutOff = false;
        auto isExpressSlot = false;
        auto isCutOffToday = false;
    }

    static immutable jsonValues = JsonValues();

    enum json = q"JSON
        {
          "week": "%s",
          "weekPrev": "%s",
          "weekNext": "%s",
          "currentWeekIndex": %s,
          "weekPrevIndex": %s,
          "weekNextIndex": %s,
          "dates": [
            {
              "date": "%s",
              "availability": [
                {
                  "id": "%s",
                  "name": "%s",
                  "hours": "%s",
                  "isAvailable": %s,
                  "price": "%s",
                  "cutOffDate": "%s",
                  "isStandardCutOff": %s,
                  "isExpressSlot": %s,
                  "isCutOffToday": %s
                }
              ]
            }
          ]
        }
JSON".format(jsonValues.tupleof);

    enum Ica.ShippingSlots expected = {
        week: jsonValues.week,
        weekPrev: jsonValues.weekPrev,
        weekNext: jsonValues.weekNext,

        currentWeekIndex: jsonValues.currentWeekIndex,
        weekPrevIndex: jsonValues.weekPrevIndex,
        weekNextIndex: jsonValues.weekNextIndex,

        dates: [{
            date: Date(2020, 4, 13),
            availability: [{
                id: jsonValues.id,
                name: jsonValues.name,
                hours: jsonValues.hours.replace(`\n`, "\n"),
                isAvailable: jsonValues.isAvailable,
                price: jsonValues.price,
                cutOffDate: DateTime(2020, 4, 12, 12, 0, 0),
                isStandardCutOff: jsonValues.isStandardCutOff,
                isExpressSlot: jsonValues.isExpressSlot,
                isCutOffToday: jsonValues.isCutOffToday
            }]
        }]
    };

    scope ica = new Ica(0);
    assert(ica.parseShippingSlots(json) == expected);
}

@("parseStores")
unittest
{
    enum id = "12954";
    enum name = "ICA Nära Kärrtorp";
    enum json = q"JSON
        {
          "forHomeDelivery": [
            {
              "id": "%s",
              "name": "%s"
            }
          ]
        }
JSON".format(id, name);

    scope ica = new Ica(0);
    const result = ica.parseStores(json);
    assert(result.front == Ica.Store("12954", name));
}
