module gds.template_renderer;

string render(Context)(string content, auto ref Context context)
    if (__traits(compiles, Context.tupleof))
{
    import std.traits : isArray, isSomeString;

    import mustache : MustacheEngine;

    alias MustacheEngine!string Mustache;

    static void fillContext(Context)
        (Mustache.Context mustacheContext, ref Context context)
    {
        static foreach (field; Context.tupleof)
        {{
            alias Type = typeof(field);
            enum name = __traits(identifier, field);
            alias fieldValue = () => __traits(getMember, context, name);

            static if (isArray!Type && !isSomeString!Type)
            {
                foreach (ref v; fieldValue())
                    fillContext(mustacheContext.addSubContext(name), v);
            }

            else
                mustacheContext[name] = fieldValue();
        }}
    }

    auto mustache = Mustache();
    scope rootContext = new Mustache.Context;
    fillContext(rootContext, context);

    return mustache.renderString(content, rootContext);
}

@("render")
{
    @("Flat context")
    unittest
    {
        static struct Context
        {
            auto foo = 3;
            auto bar = 4;
        }

        assert(render("{{ foo }} - {{ bar }}", Context()) == "3 - 4");
    }

    @("Nested context")
    unittest
    {
        static struct Foo
        {
            int foo;
        }

        static struct Context
        {
            auto foos = [Foo(1), Foo(2)];
        }

        enum temp = "{{# foos }}a {{ foo }} b{{/foos}}";

        assert(render(temp, Context()) == "a 1 ba 2 b");
    }
}
