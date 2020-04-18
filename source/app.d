import gds.config;
import gds.core.algorithm;
import gds.core.set;
import gds.database;
import gds.reporters.stdout;
import gds.reporters.reporter;
import gds.reporters.email;
import gds.store;
import gds.stores.ica;
import gds.utility;

enum Reporter
{
    stdout,
    email
}

struct Options
{
    string configPath;
    string databasePath;
    Reporter reporter;
    bool helpRequested = false;
}

Options parseCommandLine(string[] args)
{
    import std.getopt : config, GetoptResult, GetOptException, getopt, defaultGetoptPrinter;
    import std.stdio : stderr;

    enum usage = "Usage: grocery_delivery_slots options\n";
    Options options;
    alias required = config.required;

    GetoptResult helpInfo;
    try
    {
        helpInfo = getopt(
            args,
            required, "config|c", "The path to the configuration file", &options.configPath,
            required, "database|d", "The path to the database file", &options.databasePath,
            "reporter|r", "The reporter to use", &options.reporter
        );
    }

    catch (GetOptException e)
    {
        stderr.writeln(e.msg);
        helpInfo.helpWanted = true;
    }

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter(usage, helpInfo.options);
        Options result = { helpRequested: true };
        return result;
    }

    return options;

}

ShippingSlotEntry[] processAccount(string email, Account account,
    Set!SlotId slotIds, Options options, Config config)
{
    import std.algorithm : map;
    import std.array : array;
    import std.datetime : days;

    scope ica = new Ica(account.zip);

    auto stores = ica.availableShippingSlotsWithin(
        account.days.days, account.special, slotIds
    );

    scope gds.reporters.reporter.Reporter reporter;

    final switch (options.reporter)
    {
        case Reporter.stdout:
            reporter = new Stdout;
        break;

        case Reporter.email:
            reporter = new Email(email, config.emailReporter);
        break;
    }

    reporter.report(stores);

    alias toSlotEntry = (slot) {
        ShippingSlotEntry entry = {
            account: email,
            id: slot.id,
            date: slot.date
        };

        return entry;
    };

    return stores
        .flatMap!(store => store.shippingSlots)
        .map!toSlotEntry
        .array;
}

version = Thread;

void main(string[] args)
{
    import core.thread : Thread;

    import std.algorithm : each;
    import std.file : readText;

    const options = parseCommandLine(args);

    if (options.helpRequested)
        return;

    auto config = parseConfig(options.configPath.readText);
    auto database = Database.loadFromDisk(options.databasePath);
    database.removeExpiredEntries(currentDate);

    ShippingSlotEntry[] entries;
    entries.reserve(config.accounts.length);

    alias run = (email, account) =>
        processAccount(email, account, database.slotIds(email), options, config);

    version (Thread)
    {
        Thread[] threads;
        threads.reserve(config.accounts.length);

        foreach (email, account; config.accounts)
        {
            threads ~= new Thread({ entries ~= run(email, account); });
            threads[$ - 1].start;
        }

        threads.each!(thread => thread.join);
    }

    else
    {
        foreach (email, account; config.accounts)
            entries ~= run(email, account);
    }

    entries.each!(e => database.add(e));
    database.saveToDisk(options.databasePath);
}
