# Grocery Delivery Slots

This is an application that will get all the available shipping slots for the
closest [ICA](https://ica.se) stores from a given ZIP code.

It's a command line application which can report the result either to standard
out or by sending an email.

It will only report a shipping slot ones. Every time the application is run, it
will clear the database (specified using `--database`) of expired slots.

## Usage

1. Create a configuration file called `config.yml`. Here's an example:
    ```yaml
    # Settings for sending emails. This section is only required when
    # using the email reporter.
    email_reporter:
      sender:
        # Address of sender
        address: foo@gmail.com
        # Name of sender
        name: Grocery Delivery Slots

      # Server settings. For using Gmail, the account needs to have multi
      # factor authentication enabled and create an application password.
      server:
        # The address of the server to use
        address: smtps://smtp.gmail.com
        # The username
        username: foo@gmail.com
        # The password
        password: bar

    # The accounts
    accounts:
      # Account name and the email address to send emails to when using
      # the email reporter.
      foo@mail.com:
        # The ZIP code to look for stores
        zip: 12345
        # How many days forward it should look for slots
        days: 7
        # Set to `true` if slots for high risk groups be included
        special: false

      bar@mail.com:
        zip: 56789
        days: 2
        special: true
    ```

2. Run the application by invoking:

    ```
    grocery_delivery_slots --config config.yml --database database.yml --reporter stdout
    ```

    This will print all the available shipping slots to standard out.

    Or use the email reporter instead:

    ```
    grocery_delivery_slots --config config.yml --database database.yml --reporter email
    ```

## Build

1. Install a [D compiler](https://dlang.org/download.html)
2. Run `dub build` to build the application
