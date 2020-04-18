module gds.reporters.reporter;

interface Reporter
{
    import gds.store : Store;

    void report(Store[] stores);
}
