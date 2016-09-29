--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: hstore; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS hstore WITH SCHEMA public;


--
-- Name: EXTENSION hstore; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION hstore IS 'data type for storing sets of (key, value) pairs';


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_stat_statements IS 'track execution statistics of all SQL statements executed';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: postgres_fdw; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgres_fdw WITH SCHEMA public;


--
-- Name: EXTENSION postgres_fdw; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgres_fdw IS 'foreign-data wrapper for remote PostgreSQL servers';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


SET search_path = public, pg_catalog;

--
-- Name: report_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE report_status AS ENUM (
    'inactive',
    'active',
    'pausing',
    'paused'
);


--
-- Name: _final_median(numeric[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION _final_median(numeric[]) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $_$
   SELECT AVG(val)
   FROM (
     SELECT val
     FROM unnest($1) val
     ORDER BY 1
     LIMIT  2 - MOD(array_upper($1, 1), 2)
     OFFSET CEIL(array_upper($1, 1) / 2.0) - 1
   ) sub;
$_$;


--
-- Name: adminmanageurl(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION adminmanageurl(obj_class text, link_id text, name text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
  RETURN '<a href="https://staqadmin.herokuapp.com/manage/' || obj_class || '/' || link_id::TEXT || '">' || name::TEXT || '</a>';
END;
$$;


--
-- Name: all_columns_str(regclass); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION all_columns_str(_tbl regclass, OUT result text) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
    BEGIN
      -- Given a table name, returns a comma-delimited string of the columns.
      -- We use this as a fallback when trying to get a list of indexed columns.
      -- If a table doesn't have any, as for a report view that's only a row
      -- of metrics, we just return all of the columns
      EXECUTE FORMAT('
        SELECT STRING_AGG(quote_ident(column_name),'', '')
        FROM (
          SELECT column_name
          FROM information_schema.columns
          WHERE table_name = ''%s''
        )
        AS column_names',
      _tbl)
      INTO RESULT;
    END;
    $$;


--
-- Name: calculate_table_hash_aggregate(regclass); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION calculate_table_hash_aggregate(_tbl regclass, OUT result text) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
    DECLARE
      indices text;
    BEGIN
      -- Given a table name, return the MD5 hash for all of the values in that table
      -- which is a simple way to tell if a report has changed. Note that since our report views
      -- don't have an easy, generic way to guarantee sort order, this function will return
      -- different results when the report view's sort order changes, even if the data hasn't changed.
      -- See http://stackoverflow.com/q/4020033/308448

      EXECUTE FORMAT('SELECT COALESCE(indexed_columns_str(''%s''),all_columns_str(''%s''))',_tbl,_tbl)
      INTO indices;

      EXECUTE FORMAT('SELECT MD5(pg_hashagg(MD5(CAST((%s.*) AS TEXT))))
      FROM %s
      GROUP BY %s
      ORDER BY %s',
      _tbl,_tbl,indices,indices)
      INTO result;
      END;
    $$;


--
-- Name: create_inbound_email_address(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION create_inbound_email_address() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$

      DECLARE 
        is_inbound_email BOOLEAN;
      BEGIN
        EXECUTE 'SELECT EXISTS(SELECT 1 FROM extraction_engines WHERE id = $1 AND type = ''InboundEmail'')' INTO
        is_inbound_email
        USING
        NEW.extraction_engine_id;

        IF ( is_inbound_email ) THEN
          EXECUTE 'INSERT INTO inbound_email_addresses (to_address,connection_id,connection_type,created_at,updated_at)'
               || ' VALUES (''cc_''||$1||''@staqdata.com'',$1,''CustomConnection'',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)'
          USING New.id;
        END IF;

        RETURN NEW;
      END
      $_$;


--
-- Name: create_staq_event_for_insert_or_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION create_staq_event_for_insert_or_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      -- INSERT/UPDATE/DELETE events get turned into a staq_events record, and the staq_events_insert_trigger
      -- ensures sure that the staqevents app hears about it
      -- see https://github.com/staqapp/events
      INSERT INTO staq_events (name,triggered_by,table_name,table_operation,table_record_id)
      VALUES ('DatabaseRecordChange',TG_NAME || ': create_staq_event_for_insert_or_update()',TG_TABLE_NAME,TG_OP,NEW.id);

      RAISE DEBUG 'Created new staq_events record after being triggered by (%) for (%) of (%) on (%)', TG_NAME,TG_OP,TG_TABLE_NAME,NEW.id::TEXT;

      RETURN NULL;
    END
    $$;


--
-- Name: default_custom_connection_scopes_to_enabled(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION default_custom_connection_scopes_to_enabled() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$

      DECLARE
        is_custom_connection_scope BOOLEAN;
      BEGIN
        EXECUTE 'SELECT EXISTS(SELECT 1 ' ||
                              'FROM scopes sc JOIN schemas s ON (sc.schema_id = s.id) ' ||
                              'WHERE sc.id = $1 AND s.type = 3)' INTO
        is_custom_connection_scope
        USING
        NEW.id;

        IF ( is_custom_connection_scope ) THEN
          EXECUTE 'INSERT INTO data_source_scopes (data_source_id,scope_id,visible,enabled,created_at,updated_at) ' ||
                  'SELECT cc.data_source_id, sc.id, TRUE, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP ' ||
                  'FROM scopes sc JOIN custom_connections cc ON (sc.schema_id = cc.schema_id) ' ||
                  'WHERE sc.id = $1'
          USING New.id;
        END IF;

        RETURN NEW;
      END
      $_$;


--
-- Name: indexed_columns_str(regclass); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION indexed_columns_str(_tbl regclass, OUT result text) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
    BEGIN
      -- Given a table name, returns a comma-delimited string of the columns that have
      -- an index, which we take to be an indicator of how the table should be sorted
      EXECUTE FORMAT('
        SELECT STRING_AGG(quote_ident(column_name),'', '')
        FROM (
          SELECT a.attname AS column_name
          FROM pg_class t, pg_class i, pg_index ix, pg_attribute a
          WHERE t.oid = ix.indrelid
          AND i.oid = ix.indexrelid
          AND a.attrelid = t.oid
          AND a.attnum = ANY(ix.indkey)
          AND t.relkind = ''r''
          AND t.relname = ''%s''
          GROUP BY a.attname, t.relname, i.relname
          ORDER BY t.relname, i.relname)
        AS column_names',
      _tbl)
      INTO RESULT;
    END;
    $$;


--
-- Name: insert_base_report_view(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION insert_base_report_view() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
      BEGIN
        EXECUTE 'INSERT INTO report_views (report_id,user_id,created_at,updated_at)'
             || ' VALUES ($1,$2,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)'
        USING New.id,New.user_id;

        RETURN NEW;
      END
      $_$;


--
-- Name: insert_creator_report_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION insert_creator_report_user() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
      BEGIN
        EXECUTE 'INSERT INTO report_users (report_id,user_id,created_at,updated_at)'
             || ' VALUES ($1,$2,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)'
        USING New.id,New.user_id;

        RETURN New;
      END
      $_$;


--
-- Name: insert_creator_report_view_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION insert_creator_report_view_user() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
      BEGIN
        EXECUTE 'INSERT INTO report_view_users (report_view_id,user_id,created_at,updated_at)'
             || ' VALUES ($1,$2,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)'
        USING New.id,New.user_id;

        RETURN NEW;
      END
      $_$;


--
-- Name: insert_dashboard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION insert_dashboard() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
      BEGIN
        EXECUTE 'INSERT INTO dashboards (user_id,created_at,updated_at)'
             || ' VALUES ($1,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)'
        USING New.id;

        RETURN NEW;
      END
      $_$;


--
-- Name: insert_dashboard_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION insert_dashboard_user() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
      BEGIN
        EXECUTE 'INSERT INTO dashboard_users (user_id,dashboard_id,created_at,updated_at)'
             || ' VALUES ($1,$2,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)'
        USING New.user_id,New.id;

        RETURN NEW;
      END
      $_$;


--
-- Name: insert_visible_user_subscriptions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION insert_visible_user_subscriptions() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
      BEGIN
        -- Subscribe the new user for all the application notifications
        EXECUTE 'INSERT INTO user_subscriptions (user_id,subscription_id,created_at,updated_at)'
             || ' SELECT $1,s.id,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP'
             || ' FROM subscriptions s WHERE s.visible=true'
        USING New.id;

        RETURN NULL;
      END
      $_$;


--
-- Name: pg_concat(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION pg_concat(text, text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
    BEGIN
        IF $1 ISNULL THEN
          RETURN $2;
        ELSE
          RETURN $1 || $2;
        END IF;
    END;
    $_$;


--
-- Name: pg_concat_fin(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION pg_concat_fin(text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
    BEGIN
        RETURN $1;
    END;
    $_$;


--
-- Name: pi_confirm_association_exists(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION pi_confirm_association_exists() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
  id integer;
  result boolean;
BEGIN
  EXECUTE 'SELECT ($1).' || TG_ARGV[0] || '_id::integer'
  INTO id
  USING NEW;

  EXECUTE 'SELECT EXISTS(SELECT 1 FROM ' || TG_ARGV[1] || ' WHERE id = $1)'
  INTO result
  USING id;

  IF result THEN
    RETURN NEW;
  END IF;

  -- raise exception instead of return for ActiveRecord to catch
  RAISE EXCEPTION
    USING MESSAGE = 'insert or update on table "' || TG_TABLE_NAME || '" violates polymorphic integrity',
      DETAIL = 'Record with id = ' || id || ' does not exist in table "' || TG_ARGV[1] || '".';
END
$_$;


--
-- Name: pi_delete_cascade(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION pi_delete_cascade() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
BEGIN
  EXECUTE 'DELETE FROM ' || TG_ARGV[0]
       || ' WHERE ' || TG_ARGV[1] || '_id = $1 AND ' || TG_ARGV[1] || '_type = $2'
  USING OLD.id, TG_ARGV[2];

  RETURN NULL;
END
$_$;


--
-- Name: populate_reports_edited_at_by_on_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION populate_reports_edited_at_by_on_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      -- This will populate the edited_by_user_id and edited_at columns with the
      -- report creator and the created_at timestamp respectively
      NEW.edited_by_user_id := NEW.user_id;
      NEW.edited_at := NEW.created_at;

      RETURN NEW;
    END
    $$;


--
-- Name: remove_data_source(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION remove_data_source() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM data_sources WHERE id = OLD.data_source_id;
  RETURN NULL;
END
$$;


--
-- Name: remove_schema(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION remove_schema() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM schemas WHERE id = OLD.schema_id;
  RETURN NULL;
END
$$;


--
-- Name: send_new_staq_event_notice(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION send_new_staq_event_notice() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      -- this is a convenience method so the staqevents app can react quickly
      -- to newly-insert staq_events rows
      PERFORM pg_notify('new_staq_event',NEW.id::text);
      RETURN NULL;
    END
    $$;


--
-- Name: median(numeric); Type: AGGREGATE; Schema: public; Owner: -
--

CREATE AGGREGATE median(numeric) (
    SFUNC = array_append,
    STYPE = numeric[],
    INITCOND = '{}',
    FINALFUNC = _final_median
);


--
-- Name: pg_hashagg(text); Type: AGGREGATE; Schema: public; Owner: -
--

CREATE AGGREGATE pg_hashagg(text) (
    SFUNC = pg_concat,
    STYPE = text,
    FINALFUNC = pg_concat_fin
);


--
-- Name: staq_advanced_query_1; Type: SERVER; Schema: -; Owner: -
--

/* FOREIGN DATA WRAPPER SERVER INFO NOT USEFUL IN DEVELOPMENT MODE */


--
-- Name: USER MAPPING <username> SERVER staq_advanced_query_1; Type: USER MAPPING; Schema: -; Owner: -
--

/* FOREIGN DATA WRAPPER USER MAPPING INFO NOT USEFUL IN DEVELOPMENT MODE */


--
-- Name: staq_query_2; Type: SERVER; Schema: -; Owner: -
--

/* FOREIGN DATA WRAPPER SERVER INFO NOT USEFUL IN DEVELOPMENT MODE */


--
-- Name: USER MAPPING <username> SERVER staq_query_2; Type: USER MAPPING; Schema: -; Owner: -
--

/* FOREIGN DATA WRAPPER USER MAPPING INFO NOT USEFUL IN DEVELOPMENT MODE */


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: account_domains; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE account_domains (
    id integer NOT NULL,
    name character varying(255) DEFAULT ''::character varying NOT NULL,
    account_id integer NOT NULL,
    admin_id integer,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT account_domains_name_present CHECK ((length(btrim((name)::text)) > 0))
);


--
-- Name: account_domains_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE account_domains_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: account_domains_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE account_domains_id_seq OWNED BY account_domains.id;


--
-- Name: account_state_transitions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE account_state_transitions (
    id integer NOT NULL,
    account_id integer,
    event character varying(255),
    "from" character varying(255),
    "to" character varying(255),
    message text,
    created_at timestamp without time zone
);


--
-- Name: account_state_transitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE account_state_transitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: account_state_transitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE account_state_transitions_id_seq OWNED BY account_state_transitions.id;


--
-- Name: account_tokens; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE account_tokens (
    id integer NOT NULL,
    account_id integer NOT NULL,
    token_prefix text NOT NULL,
    hashed_token text NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: account_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE account_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: account_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE account_tokens_id_seq OWNED BY account_tokens.id;


--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE accounts (
    id integer NOT NULL,
    name character varying(255) DEFAULT ''::character varying NOT NULL,
    domain character varying(255) DEFAULT NULL::character varying,
    logo_url character varying(255) DEFAULT ''::character varying NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    url character varying(255) DEFAULT ''::character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    favicon_url character varying(255) DEFAULT ''::character varying NOT NULL,
    state character varying(255) DEFAULT 'free'::character varying NOT NULL,
    user_limit integer DEFAULT 1 NOT NULL,
    platform_limit integer DEFAULT 0 NOT NULL,
    connection_limit integer DEFAULT 0 NOT NULL,
    trial boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    sftp_account_name character varying(255) DEFAULT 'staqtest'::character varying NOT NULL,
    notes text DEFAULT ''::text NOT NULL,
    custom_connection_limit integer DEFAULT 0 NOT NULL,
    contract_unit_count integer DEFAULT 20 NOT NULL,
    contract_unit_price numeric(18,2) DEFAULT 0 NOT NULL,
    contract_discount numeric(18,2) DEFAULT 0 NOT NULL,
    contract_billing_schedule character varying(255) DEFAULT ''::character varying NOT NULL,
    contract_date timestamp without time zone,
    contract_renewal_date timestamp without time zone,
    report_status report_status DEFAULT 'active'::report_status,
    CONSTRAINT accounts_user_limit_positive CHECK ((user_limit >= 0))
);


--
-- Name: accounts_admins; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE accounts_admins (
    id integer NOT NULL,
    account_id integer NOT NULL,
    admin_id integer NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: accounts_admins_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE accounts_admins_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounts_admins_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE accounts_admins_id_seq OWNED BY accounts_admins.id;


--
-- Name: accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE accounts_id_seq OWNED BY accounts.id;


--
-- Name: admins; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE admins (
    id integer NOT NULL,
    email character varying(255) DEFAULT NULL::character varying NOT NULL,
    current_sign_in_at timestamp without time zone,
    last_sign_in_at timestamp without time zone,
    current_sign_in_ip character varying(255),
    last_sign_in_ip character varying(255),
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    identifier uuid DEFAULT uuid_generate_v4(),
    can_view_sensitive_data boolean DEFAULT false NOT NULL,
    aws_multi_factor_auth_identifier character varying(255),
    name character varying(255) DEFAULT ''::character varying NOT NULL,
    role character varying(255) DEFAULT ''::character varying NOT NULL,
    team character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: admins_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE admins_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: admins_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE admins_id_seq OWNED BY admins.id;


--
-- Name: announcements; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE announcements (
    id integer NOT NULL,
    admin_id integer,
    subject character varying(255) DEFAULT ''::character varying NOT NULL,
    message text DEFAULT ''::text NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    sent_at timestamp without time zone
);


--
-- Name: announcements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE announcements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: announcements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE announcements_id_seq OWNED BY announcements.id;


--
-- Name: applets; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE applets (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    user_id integer NOT NULL,
    settings text,
    "order" integer DEFAULT 0 NOT NULL,
    report_view_id integer NOT NULL,
    dashboard_id integer NOT NULL,
    CONSTRAINT applets_name_present CHECK ((length(btrim((name)::text)) > 0))
);


--
-- Name: applets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE applets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: applets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE applets_id_seq OWNED BY applets.id;


--
-- Name: applications; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE applications (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    type character varying(255) NOT NULL,
    code text,
    last_pushed_by character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    public boolean DEFAULT true NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    CONSTRAINT applications_name_present CHECK ((length(btrim((name)::text)) > 0)),
    CONSTRAINT applications_type_present CHECK ((length(btrim((type)::text)) > 0))
);


--
-- Name: applications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE applications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: applications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE applications_id_seq OWNED BY applications.id;


--
-- Name: authentication_tokens; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE authentication_tokens (
    id uuid DEFAULT uuid_generate_v4() NOT NULL,
    active boolean DEFAULT true,
    user_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE categories (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE categories_id_seq OWNED BY categories.id;


--
-- Name: collection_mission_loading_batches; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE collection_mission_loading_batches (
    "Load Group" text,
    "Load Group Advisory Lock ID" integer,
    "Earliest Mission Created At" text,
    "Earliest Mission Scheduled At" text,
    "# of Missions" bigint,
    "Mission IDs" integer[]
);

ALTER TABLE ONLY collection_mission_loading_batches REPLICA IDENTITY NOTHING;


--
-- Name: collection_mission_state_transitions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE collection_mission_state_transitions (
    id integer NOT NULL,
    collection_mission_id integer NOT NULL,
    event character varying(255),
    "from" character varying(255),
    "to" character varying(255) DEFAULT 'new'::character varying NOT NULL,
    message text,
    backtrace text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: collection_mission_state_transitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE collection_mission_state_transitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: collection_mission_state_transitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE collection_mission_state_transitions_id_seq OWNED BY collection_mission_state_transitions.id;


--
-- Name: collection_mission_tasks; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE collection_mission_tasks (
    id integer NOT NULL,
    collection_mission_id integer NOT NULL,
    success boolean,
    message text DEFAULT ''::text NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    options text,
    datapoint_count integer DEFAULT 0 NOT NULL,
    load_keys text,
    job_id character varying(255),
    name character varying(255) DEFAULT ''::character varying NOT NULL,
    step_args text,
    subtask_of_task_id integer,
    auth_failure boolean DEFAULT false NOT NULL,
    exception_count integer DEFAULT 0 NOT NULL,
    last_exception text DEFAULT ''::text NOT NULL,
    latest_data_at timestamp without time zone,
    perform_in_seconds integer DEFAULT 0 NOT NULL,
    task_started_at timestamp without time zone,
    task_finished_at timestamp without time zone,
    num_attempts integer DEFAULT 0 NOT NULL,
    run_location character varying(255),
    earliest_data_at timestamp without time zone,
    scheduled_at timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: collection_missions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE collection_missions (
    id integer NOT NULL,
    connection_id integer NOT NULL,
    state character varying(255) DEFAULT 'new'::character varying NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    file_keys text,
    verify_only boolean DEFAULT false NOT NULL,
    sidekiq_batch_id character varying(255) DEFAULT ''::character varying NOT NULL,
    datapoint_count integer DEFAULT 0 NOT NULL,
    connection_type character varying(255) NOT NULL,
    schema_version integer DEFAULT 0 NOT NULL,
    rerun boolean DEFAULT false NOT NULL,
    load_jid character varying(255),
    scheduled_at timestamp without time zone DEFAULT now() NOT NULL,
    interactive boolean DEFAULT false NOT NULL,
    mission_start_at timestamp without time zone NOT NULL,
    mission_end_at timestamp without time zone NOT NULL,
    latest_data_at timestamp without time zone,
    troubleshooting_file_keys text,
    target_id integer,
    target_type character varying(255),
    started_at timestamp without time zone,
    earliest_data_at timestamp without time zone,
    worker_name text,
    triggered_by text DEFAULT 'UNKNOWN'::text NOT NULL,
    CONSTRAINT interval_order_check CHECK ((mission_start_at <= mission_end_at))
);


--
-- Name: collection_missions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE collection_missions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: collection_missions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE collection_missions_id_seq OWNED BY collection_missions.id;


--
-- Name: configurations; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE configurations (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    value text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    CONSTRAINT configurations_name_format CHECK (((name)::text ~ '^[_a-z0-9]+$'::text))
);


--
-- Name: configurations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE configurations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: configurations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE configurations_id_seq OWNED BY configurations.id;


--
-- Name: connection_issues; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE connection_issues (
    id integer NOT NULL,
    issue_id integer NOT NULL,
    connection_id integer NOT NULL
);


--
-- Name: connection_issues_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE connection_issues_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: connection_issues_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE connection_issues_id_seq OWNED BY connection_issues.id;


--
-- Name: connection_semaphores; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE connection_semaphores (
    id integer NOT NULL,
    connection_id integer NOT NULL,
    size integer DEFAULT 1 NOT NULL,
    timeout_seconds integer DEFAULT 3600 NOT NULL
);


--
-- Name: connection_semaphores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE connection_semaphores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: connection_semaphores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE connection_semaphores_id_seq OWNED BY connection_semaphores.id;


--
-- Name: connections; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE connections (
    id integer NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    params text,
    params_key text,
    params_iv text,
    name character varying(255) DEFAULT ''::character varying NOT NULL,
    platform_id integer NOT NULL,
    account_id integer NOT NULL,
    state character varying(255) DEFAULT 'New'::character varying NOT NULL,
    state_message character varying(255) DEFAULT ''::character varying NOT NULL,
    time_zone character varying(255) DEFAULT 'UTC'::character varying NOT NULL,
    latest_data_at timestamp without time zone,
    deleted boolean DEFAULT false NOT NULL,
    data_source_id integer NOT NULL,
    authorization_unstable_at timestamp without time zone,
    custom_extraction_scheduling_recipe_id integer,
    created_by_user_id integer,
    maintenance_start_at timestamp without time zone,
    maintenance_by_admin_id integer,
    billable boolean DEFAULT true NOT NULL,
    earliest_data_at timestamp without time zone,
    internal_notes text,
    ignore_health boolean DEFAULT false,
    CONSTRAINT connections_state_whitelist CHECK (((state)::text = ANY (ARRAY[('New'::character varying)::text, ('Available'::character varying)::text, ('Unavailable'::character varying)::text])))
);


--
-- Name: connections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE connections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: connections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE connections_id_seq OWNED BY connections.id;


--
-- Name: control_mission_state_transitions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE control_mission_state_transitions (
    id integer NOT NULL,
    control_mission_id integer NOT NULL,
    event character varying(255),
    "from" character varying(255),
    "to" character varying(255),
    message text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: control_mission_state_transitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE control_mission_state_transitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: control_mission_state_transitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE control_mission_state_transitions_id_seq OWNED BY control_mission_state_transitions.id;


--
-- Name: control_mission_tasks; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE control_mission_tasks (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    control_mission_id integer NOT NULL,
    state character varying(255) DEFAULT 'new'::character varying NOT NULL,
    sidekiq_job_id character varying(255),
    options text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    exception_count integer DEFAULT 0 NOT NULL,
    last_message text,
    CONSTRAINT control_mission_tasks_state_whitelist CHECK (((state)::text = ANY (ARRAY[('new'::character varying)::text, ('in_progress'::character varying)::text, ('success'::character varying)::text, ('failure'::character varying)::text])))
);


--
-- Name: control_mission_tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE control_mission_tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: control_mission_tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE control_mission_tasks_id_seq OWNED BY control_mission_tasks.id;


--
-- Name: control_missions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE control_missions (
    id integer NOT NULL,
    state character varying(255) DEFAULT 'new'::character varying NOT NULL,
    triggered_by character varying(255) NOT NULL,
    sidekiq_batch_id character varying(255),
    options text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    installed_report_application_id integer NOT NULL,
    CONSTRAINT control_missions_state_whitelist CHECK (((state)::text = ANY (ARRAY[('new'::character varying)::text, ('in_progress'::character varying)::text, ('success'::character varying)::text, ('failure'::character varying)::text])))
);


--
-- Name: control_missions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE control_missions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: control_missions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE control_missions_id_seq OWNED BY control_missions.id;


--
-- Name: cube_match_dimensions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE cube_match_dimensions (
    id integer NOT NULL,
    domain character varying(255),
    "column" character varying(255) NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    source_id integer NOT NULL,
    source_type character varying(255) NOT NULL,
    scope_id integer NOT NULL,
    CONSTRAINT cube_match_dimensions_source_type_whitelist CHECK (((source_type)::text = ANY (ARRAY[('Connection'::character varying)::text, ('CustomConnection'::character varying)::text, ('Platform'::character varying)::text, ('Report'::character varying)::text])))
);


--
-- Name: cube_match_dimensions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE cube_match_dimensions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cube_match_dimensions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE cube_match_dimensions_id_seq OWNED BY cube_match_dimensions.id;


--
-- Name: cube_match_values; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE cube_match_values (
    id integer NOT NULL,
    cube_match_id integer NOT NULL,
    cube_match_dimension_id integer NOT NULL,
    "row" character varying(255) NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: cube_match_values_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE cube_match_values_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cube_match_values_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE cube_match_values_id_seq OWNED BY cube_match_values.id;


--
-- Name: cube_matches; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE cube_matches (
    id integer NOT NULL,
    cube_id integer NOT NULL,
    cube_match_dimension_id integer NOT NULL,
    "row" character varying(255) NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: cube_matches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE cube_matches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cube_matches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE cube_matches_id_seq OWNED BY cube_matches.id;


--
-- Name: cube_rules; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE cube_rules (
    id integer NOT NULL,
    type character varying(255) NOT NULL,
    definition text NOT NULL,
    cube_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: cube_rules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE cube_rules_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cube_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE cube_rules_id_seq OWNED BY cube_rules.id;


--
-- Name: cubes; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE cubes (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    account_id integer NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: cubes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE cubes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cubes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE cubes_id_seq OWNED BY cubes.id;


--
-- Name: custom_connection_issues; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE custom_connection_issues (
    id integer NOT NULL,
    issue_id integer NOT NULL,
    custom_connection_id integer NOT NULL
);


--
-- Name: custom_connection_issues_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE custom_connection_issues_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: custom_connection_issues_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE custom_connection_issues_id_seq OWNED BY custom_connection_issues.id;


--
-- Name: custom_connections; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE custom_connections (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    account_id integer NOT NULL,
    extraction_engine_type character varying(255) NOT NULL,
    state character varying(255) DEFAULT 'New'::character varying NOT NULL,
    params text,
    params_key text,
    params_iv text,
    time_zone character varying(255) DEFAULT 'UTC'::character varying NOT NULL,
    scheduling_strategy text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    state_message character varying(255) DEFAULT ''::character varying NOT NULL,
    latest_data_at timestamp without time zone,
    deleted boolean DEFAULT false NOT NULL,
    schema_id integer NOT NULL,
    data_source_id integer NOT NULL,
    authorization_unstable_at timestamp without time zone,
    custom_extraction_scheduling_recipe_id integer NOT NULL,
    created_by_user_id integer,
    subdirectory_name character varying(255),
    download_link_matcher character varying(255),
    sftp_account_name character varying(255),
    lookup_code character varying(255) DEFAULT md5((random())::text) NOT NULL,
    maintenance_start_at timestamp without time zone,
    maintenance_by_admin_id integer,
    billable boolean DEFAULT true NOT NULL,
    extraction_engine_id integer NOT NULL,
    earliest_data_at timestamp without time zone,
    use_date_for_reporting boolean DEFAULT true NOT NULL,
    internal_notes text,
    ignore_health boolean DEFAULT false,
    CONSTRAINT custom_connections_state_whitelist CHECK (((state)::text = ANY (ARRAY[('New'::character varying)::text, ('Available'::character varying)::text, ('Unavailable'::character varying)::text])))
);


--
-- Name: custom_connections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE custom_connections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: custom_connections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE custom_connections_id_seq OWNED BY custom_connections.id;


--
-- Name: custom_fields; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE custom_fields (
    id integer NOT NULL,
    data_source_scope_id integer NOT NULL,
    name character varying(255) NOT NULL,
    definition text NOT NULL,
    visible boolean DEFAULT true NOT NULL
);


--
-- Name: custom_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE custom_fields_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: custom_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE custom_fields_id_seq OWNED BY custom_fields.id;


--
-- Name: customer_favicons; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE customer_favicons (
    id integer NOT NULL,
    filename character varying(255) NOT NULL,
    url text NOT NULL,
    size integer DEFAULT 0 NOT NULL,
    mimetype character varying(255),
    location character varying(255),
    container character varying(255),
    key character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: customer_favicons_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE customer_favicons_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customer_favicons_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE customer_favicons_id_seq OWNED BY customer_favicons.id;


--
-- Name: customer_logos; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE customer_logos (
    id integer NOT NULL,
    filename character varying(255) NOT NULL,
    url text NOT NULL,
    size integer DEFAULT 0 NOT NULL,
    mimetype character varying(255),
    location character varying(255),
    container character varying(255),
    key character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: customer_logos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE customer_logos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customer_logos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE customer_logos_id_seq OWNED BY customer_logos.id;


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE customers (
    id integer NOT NULL,
    name character varying(255),
    email character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    password_digest character varying(255)
);


--
-- Name: customers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE customers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE customers_id_seq OWNED BY customers.id;


--
-- Name: dashboard_users; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE dashboard_users (
    id integer NOT NULL,
    user_id integer NOT NULL,
    dashboard_id integer NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    sharer_user_id integer
);


--
-- Name: dashboard_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE dashboard_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dashboard_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE dashboard_users_id_seq OWNED BY dashboard_users.id;


--
-- Name: dashboards; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE dashboards (
    id integer NOT NULL,
    user_id integer NOT NULL,
    name character varying(255) DEFAULT 'Default Dashboard'::character varying NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: dashboards_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE dashboards_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dashboards_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE dashboards_id_seq OWNED BY dashboards.id;


--
-- Name: data_source_fields; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE data_source_fields (
    id integer NOT NULL,
    data_source_scope_id integer NOT NULL,
    field_id integer NOT NULL,
    label character varying(255),
    visible boolean DEFAULT true NOT NULL
);


--
-- Name: data_source_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE data_source_fields_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: data_source_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE data_source_fields_id_seq OWNED BY data_source_fields.id;


--
-- Name: data_source_scopes; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE data_source_scopes (
    id integer NOT NULL,
    data_source_id integer NOT NULL,
    scope_id integer NOT NULL,
    visible boolean DEFAULT false NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    CONSTRAINT visible_false_if_disabled CHECK ((enabled OR (visible IS FALSE)))
);


--
-- Name: data_source_scopes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE data_source_scopes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: data_source_scopes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE data_source_scopes_id_seq OWNED BY data_source_scopes.id;


--
-- Name: data_sources; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE data_sources (
    id integer NOT NULL,
    type integer NOT NULL
);


--
-- Name: data_sources_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE data_sources_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: data_sources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE data_sources_id_seq OWNED BY data_sources.id;


--
-- Name: email_layouts; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE email_layouts (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    html text NOT NULL,
    text text NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    CONSTRAINT email_layouts_html_format CHECK ((html ~ '<%= yield %>'::text)),
    CONSTRAINT email_layouts_text_format CHECK ((text ~ '<%= yield %>'::text))
);


--
-- Name: email_layouts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE email_layouts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: email_layouts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE email_layouts_id_seq OWNED BY email_layouts.id;


--
-- Name: email_templates; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE email_templates (
    id integer NOT NULL,
    email_layout_id integer NOT NULL,
    name character varying(255) NOT NULL,
    subject character varying(255) NOT NULL,
    html text NOT NULL,
    text text DEFAULT ''::text NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: email_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE email_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: email_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE email_templates_id_seq OWNED BY email_templates.id;


--
-- Name: extraction_engines; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE extraction_engines (
    id integer NOT NULL,
    type character varying(255) NOT NULL,
    image_url character varying(255) DEFAULT ''::character varying NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    label character varying(255) DEFAULT ''::character varying NOT NULL,
    is_public boolean DEFAULT true NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    auth_provider character varying(255) DEFAULT ''::character varying NOT NULL,
    CONSTRAINT extraction_engines_type_present CHECK ((length(btrim((type)::text)) > 0))
);


--
-- Name: extraction_engines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE extraction_engines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: extraction_engines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE extraction_engines_id_seq OWNED BY extraction_engines.id;


--
-- Name: extraction_scheduling_recipes; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE extraction_scheduling_recipes (
    id integer NOT NULL,
    strategy character varying(255) NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    max_duration character varying(255),
    earliest_available_data character varying(255),
    latest_available_data character varying(255),
    extra_duration character varying(255),
    includes_today boolean DEFAULT false NOT NULL,
    notes text DEFAULT ''::text NOT NULL,
    run_at_hour integer DEFAULT 8 NOT NULL,
    CONSTRAINT extraction_scheduling_recipes_strategy_present CHECK ((length(btrim((strategy)::text)) > 0))
);


--
-- Name: extraction_scheduling_recipes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE extraction_scheduling_recipes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: extraction_scheduling_recipes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE extraction_scheduling_recipes_id_seq OWNED BY extraction_scheduling_recipes.id;


--
-- Name: extractor_assets; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE extractor_assets (
    id integer NOT NULL,
    extractor_id integer NOT NULL,
    file_name character varying(255) NOT NULL,
    file bytea NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: extractor_assets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE extractor_assets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: extractor_assets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE extractor_assets_id_seq OWNED BY extractor_assets.id;


--
-- Name: extractor_issues; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE extractor_issues (
    id integer NOT NULL,
    issue_id integer NOT NULL,
    extractor_id integer NOT NULL
);


--
-- Name: extractor_issues_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE extractor_issues_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: extractor_issues_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE extractor_issues_id_seq OWNED BY extractor_issues.id;


--
-- Name: extractor_rate_limits; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE extractor_rate_limits (
    id integer NOT NULL,
    extractor_id integer NOT NULL,
    threshold integer NOT NULL,
    interval_seconds integer NOT NULL,
    description text DEFAULT ''::text NOT NULL
);


--
-- Name: extractor_rate_limits_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE extractor_rate_limits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: extractor_rate_limits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE extractor_rate_limits_id_seq OWNED BY extractor_rate_limits.id;


--
-- Name: extractor_semaphores; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE extractor_semaphores (
    id integer NOT NULL,
    extractor_id integer NOT NULL,
    size integer DEFAULT 1 NOT NULL,
    timeout_seconds integer DEFAULT 3600 NOT NULL
);


--
-- Name: extractor_semaphores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE extractor_semaphores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: extractor_semaphores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE extractor_semaphores_id_seq OWNED BY extractor_semaphores.id;


--
-- Name: extractor_time_zone_specifications; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE extractor_time_zone_specifications (
    id integer NOT NULL,
    extractor_id integer NOT NULL,
    style integer NOT NULL,
    global_default character varying(255),
    configurable_choices text[] DEFAULT '{}'::text[],
    instructions text DEFAULT ''::text NOT NULL,
    staq_notes text DEFAULT ''::text NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    CONSTRAINT global_style_requires_nonblank_default CHECK (((style <> 0) OR (length(btrim((global_default)::text)) > 0)))
);


--
-- Name: extractor_time_zone_specifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE extractor_time_zone_specifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: extractor_time_zone_specifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE extractor_time_zone_specifications_id_seq OWNED BY extractor_time_zone_specifications.id;


--
-- Name: extractors; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE extractors (
    id integer NOT NULL,
    type character varying(255) DEFAULT NULL::character varying NOT NULL,
    "fetch" text DEFAULT ''::text NOT NULL,
    parse text DEFAULT ''::text NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    last_pushed_by character varying(255) DEFAULT ''::character varying NOT NULL,
    auth_provider character varying(255),
    prompts text,
    available boolean DEFAULT false NOT NULL,
    history text,
    instructions text DEFAULT ''::text NOT NULL,
    sikuli boolean DEFAULT false NOT NULL,
    exclude_from_last_month_collection boolean DEFAULT false NOT NULL,
    schema_id integer NOT NULL,
    extraction_scheduling_recipe_id integer NOT NULL,
    exclude_from_automatic_scheduling boolean DEFAULT false NOT NULL,
    use_date_for_reporting boolean DEFAULT true NOT NULL,
    dateless boolean DEFAULT false NOT NULL,
    exclude_from_last_seven_collection boolean DEFAULT false NOT NULL
);


--
-- Name: extractors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE extractors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: extractors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE extractors_id_seq OWNED BY extractors.id;


--
-- Name: feature_flags; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE feature_flags (
    id integer NOT NULL,
    name text NOT NULL,
    flaggable_type text NOT NULL,
    flaggable_id integer NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: feature_flags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE feature_flags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: feature_flags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE feature_flags_id_seq OWNED BY feature_flags.id;


--
-- Name: field_bak; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE field_bak (
    id integer,
    name character varying
);


--
-- Name: fields; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE fields (
    id integer NOT NULL,
    scope_id integer NOT NULL,
    name character varying(255) NOT NULL,
    label character varying(255),
    type character varying(255) NOT NULL,
    column_type character varying(255) NOT NULL,
    options text,
    scaling_factor double precision DEFAULT 1.0 NOT NULL,
    format character varying(255),
    is_unique_key boolean DEFAULT false NOT NULL,
    CONSTRAINT fields_name_present CHECK ((length(btrim((name)::text)) > 0))
);


--
-- Name: fields_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE fields_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE fields_id_seq OWNED BY fields.id;


--
-- Name: inbound_email_addresses; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE inbound_email_addresses (
    id integer NOT NULL,
    to_address citext NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    connection_id integer NOT NULL,
    connection_type character varying(255) NOT NULL,
    CONSTRAINT inbound_email_addresses_to_address_present CHECK ((length(btrim((to_address)::text)) > 0))
);


--
-- Name: inbound_email_addresses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE inbound_email_addresses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inbound_email_addresses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE inbound_email_addresses_id_seq OWNED BY inbound_email_addresses.id;


--
-- Name: inbound_email_attachments; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE inbound_email_attachments (
    id integer NOT NULL,
    inbound_email_message_id integer NOT NULL,
    url character varying(255) NOT NULL,
    file_name character varying(255) NOT NULL,
    content_type character varying(255) NOT NULL,
    size integer DEFAULT 0 NOT NULL,
    disposition character varying(255) DEFAULT ''::character varying NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    content_id character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: inbound_email_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE inbound_email_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inbound_email_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE inbound_email_attachments_id_seq OWNED BY inbound_email_attachments.id;


--
-- Name: inbound_email_messages; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE inbound_email_messages (
    id integer NOT NULL,
    from_address character varying(255) NOT NULL,
    subject character varying(255) NOT NULL,
    recipients character varying(255)[] DEFAULT '{}'::character varying[],
    html_body text DEFAULT ''::text NOT NULL,
    plain_body text DEFAULT ''::text NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    headers hstore,
    inbound_email_address_id integer NOT NULL
);


--
-- Name: inbound_email_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE inbound_email_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inbound_email_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE inbound_email_messages_id_seq OWNED BY inbound_email_messages.id;


--
-- Name: inbound_files; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE inbound_files (
    id integer NOT NULL,
    path character varying(255) NOT NULL,
    action character varying(255) NOT NULL,
    interface character varying(255) NOT NULL,
    custom_connection_id integer NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    container character varying(255),
    key character varying(255),
    url text,
    username character varying(255) DEFAULT 'UNKNOWN'::character varying NOT NULL
);


--
-- Name: inbound_files_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE inbound_files_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inbound_files_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE inbound_files_id_seq OWNED BY inbound_files.id;


--
-- Name: inbound_google_files; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE inbound_google_files (
    id integer NOT NULL,
    file_id character varying(255),
    custom_connection_id integer NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: inbound_google_files_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE inbound_google_files_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inbound_google_files_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE inbound_google_files_id_seq OWNED BY inbound_google_files.id;


--
-- Name: installed_report_applications; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE installed_report_applications (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    options text,
    enabled boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    application_id integer NOT NULL,
    report_id integer NOT NULL,
    run_on_report_change boolean DEFAULT false NOT NULL,
    options_key text,
    options_iv text,
    revealable_options hstore,
    backup_options text,
    billable boolean DEFAULT true NOT NULL
);


--
-- Name: installed_report_applications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE installed_report_applications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: installed_report_applications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE installed_report_applications_id_seq OWNED BY installed_report_applications.id;


--
-- Name: issues; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE issues (
    id integer NOT NULL,
    vendor character varying(255) NOT NULL,
    vendor_id character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    url character varying(255) DEFAULT ''::character varying NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    created_by character varying(255) NOT NULL
);


--
-- Name: issues_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE issues_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: issues_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE issues_id_seq OWNED BY issues.id;


--
-- Name: line_items; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE line_items (
    id integer NOT NULL,
    order_id integer,
    product_id integer,
    quantity integer,
    price numeric,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: line_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE line_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: line_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE line_items_id_seq OWNED BY line_items.id;


--
-- Name: loaded_tables; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE loaded_tables (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: loaded_tables_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE loaded_tables_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: loaded_tables_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE loaded_tables_id_seq OWNED BY loaded_tables.id;


--
-- Name: new_collection_mission_tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE new_collection_mission_tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: new_collection_mission_tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE new_collection_mission_tasks_id_seq OWNED BY collection_mission_tasks.id;


--
-- Name: notification_deliveries; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE notification_deliveries (
    id integer NOT NULL,
    notification_id integer NOT NULL,
    state character varying(255) DEFAULT 'new'::character varying NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    CONSTRAINT notification_deliveries_state_whitelist CHECK (((state)::text = ANY (ARRAY[('new'::character varying)::text, ('dispatched'::character varying)::text, ('delivered'::character varying)::text, ('retryable_failure'::character varying)::text, ('undeliverable'::character varying)::text])))
);


--
-- Name: notification_deliveries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE notification_deliveries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notification_deliveries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE notification_deliveries_id_seq OWNED BY notification_deliveries.id;


--
-- Name: notification_delivery_state_transitions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE notification_delivery_state_transitions (
    id integer NOT NULL,
    notification_delivery_id integer NOT NULL,
    event character varying(255),
    "from" character varying(255),
    "to" character varying(255),
    message text,
    created_at timestamp without time zone
);


--
-- Name: notification_delivery_state_transitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE notification_delivery_state_transitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notification_delivery_state_transitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE notification_delivery_state_transitions_id_seq OWNED BY notification_delivery_state_transitions.id;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE notifications (
    id integer NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    acknowledged_at timestamp without time zone,
    source_id integer NOT NULL,
    source_type character varying(255) NOT NULL,
    user_id integer NOT NULL,
    subscription_id integer NOT NULL
);


--
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE notifications_id_seq OWNED BY notifications.id;


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE orders (
    id integer NOT NULL,
    customer_id integer,
    placed_at timestamp without time zone,
    total_amount numeric,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE orders_id_seq OWNED BY orders.id;


--
-- Name: param_templates; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE param_templates (
    id integer NOT NULL,
    name character varying(255) DEFAULT ''::character varying NOT NULL,
    extraction_engine_id integer NOT NULL,
    params text,
    download_link_matcher character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: param_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE param_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: param_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE param_templates_id_seq OWNED BY param_templates.id;


--
-- Name: password_resets; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE password_resets (
    id integer NOT NULL,
    customer_id_id integer,
    token character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: password_resets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE password_resets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: password_resets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE password_resets_id_seq OWNED BY password_resets.id;


--
-- Name: plan_categories; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE plan_categories (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    label character varying(255),
    description character varying(255),
    "order" integer DEFAULT 0 NOT NULL,
    free character varying(255),
    basic character varying(255),
    professional character varying(255),
    enterprise character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    visible boolean DEFAULT true NOT NULL,
    usage boolean DEFAULT false NOT NULL,
    standard character varying(255)
);


--
-- Name: plan_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE plan_categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: plan_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE plan_categories_id_seq OWNED BY plan_categories.id;


--
-- Name: platform_categories; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE platform_categories (
    id integer NOT NULL,
    platform_id integer NOT NULL,
    category_id integer NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: platform_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE platform_categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: platform_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE platform_categories_id_seq OWNED BY platform_categories.id;


--
-- Name: platforms; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE platforms (
    id integer NOT NULL,
    title character varying(255) NOT NULL,
    image_url character varying(255),
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    info text DEFAULT ''::text NOT NULL,
    is_public boolean DEFAULT true NOT NULL,
    extractor_id integer,
    favicon_url character varying(255) DEFAULT ''::character varying NOT NULL,
    data_source_id integer NOT NULL
);


--
-- Name: platforms_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE platforms_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: platforms_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE platforms_id_seq OWNED BY platforms.id;


--
-- Name: products; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE products (
    id integer NOT NULL,
    name character varying(255),
    price numeric,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE products_id_seq OWNED BY products.id;


--
-- Name: protected_operations; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE protected_operations (
    id integer NOT NULL,
    record_type character varying(255) NOT NULL,
    operation character varying(255) NOT NULL,
    staq_notes text DEFAULT ''::text NOT NULL
);


--
-- Name: protected_operations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE protected_operations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: protected_operations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE protected_operations_id_seq OWNED BY protected_operations.id;


--
-- Name: rails_admin_histories; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE rails_admin_histories (
    id integer NOT NULL,
    message text,
    username character varying(255),
    item integer,
    "table" character varying(255),
    month smallint,
    year bigint,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: rails_admin_histories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE rails_admin_histories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: rails_admin_histories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE rails_admin_histories_id_seq OWNED BY rails_admin_histories.id;


--
-- Name: report_column_def_backups; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_column_def_backups (
    id integer NOT NULL,
    report_column_id integer,
    definition text NOT NULL
);


--
-- Name: report_column_def_backups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_column_def_backups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_column_def_backups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_column_def_backups_id_seq OWNED BY report_column_def_backups.id;


--
-- Name: report_column_fields; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_column_fields (
    id integer NOT NULL,
    report_column_id integer NOT NULL,
    type character varying(255) NOT NULL,
    field_id integer,
    report_custom_field_id integer,
    value character varying(255),
    data_source_id integer,
    display_order integer
);


--
-- Name: report_column_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_column_fields_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_column_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_column_fields_id_seq OWNED BY report_column_fields.id;


--
-- Name: report_column_filters; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_column_filters (
    id integer NOT NULL,
    report_column_id integer NOT NULL,
    report_filter_id integer NOT NULL,
    display_order integer
);


--
-- Name: report_column_filters_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_column_filters_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_column_filters_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_column_filters_id_seq OWNED BY report_column_filters.id;


--
-- Name: report_columns; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_columns (
    id integer NOT NULL,
    report_id integer NOT NULL,
    column_id character varying(255) NOT NULL,
    label character varying(255) NOT NULL,
    type character varying(255) NOT NULL,
    column_type character varying(255) NOT NULL,
    definition text,
    style character varying(255),
    hide boolean,
    "default" character varying(255),
    sort_direction character varying(255),
    sort_priority integer,
    summarization character varying(255),
    total character varying(255),
    steps text,
    display_order integer,
    field_id integer,
    is_unique_key boolean DEFAULT false NOT NULL,
    "precision" integer DEFAULT 0 NOT NULL,
    group_by boolean DEFAULT false,
    base_type character varying(255) NOT NULL
);


--
-- Name: report_columns_bak; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_columns_bak (
    id integer,
    report_id integer,
    column_id character varying(255),
    label character varying(255),
    type character varying(255),
    column_type character varying(255),
    definition text,
    style character varying(255),
    hide boolean,
    "default" character varying(255),
    sort_direction character varying(255),
    sort_priority integer,
    summarization character varying(255),
    total character varying(255),
    steps text,
    display_order integer,
    field_id integer,
    is_unique_key boolean,
    "precision" integer,
    group_by boolean
);


--
-- Name: report_columns_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_columns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_columns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_columns_id_seq OWNED BY report_columns.id;


--
-- Name: report_comments; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_comments (
    id integer NOT NULL,
    report_id integer NOT NULL,
    user_id integer NOT NULL,
    message text DEFAULT ''::text NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: report_comments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_comments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_comments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_comments_id_seq OWNED BY report_comments.id;


--
-- Name: report_custom_fields; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_custom_fields (
    id integer NOT NULL,
    report_id integer NOT NULL,
    custom_field_id integer NOT NULL
);


--
-- Name: report_custom_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_custom_fields_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_custom_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_custom_fields_id_seq OWNED BY report_custom_fields.id;


--
-- Name: report_data_source_filters; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_data_source_filters (
    id integer NOT NULL,
    report_data_source_id integer NOT NULL,
    report_filter_id integer NOT NULL,
    field_id integer NOT NULL,
    display_order integer
);


--
-- Name: report_data_source_filters_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_data_source_filters_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_data_source_filters_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_data_source_filters_id_seq OWNED BY report_data_source_filters.id;


--
-- Name: report_data_sources; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_data_sources (
    id integer NOT NULL,
    report_id integer NOT NULL,
    data_source_id integer NOT NULL,
    old_scope_name character varying(255),
    lookup_column character varying(255),
    most_recent_data_at timestamp without time zone,
    last_successful_collection_at timestamp without time zone,
    lookup_join_type character varying(255),
    scope_id integer NOT NULL
);


--
-- Name: report_data_sources_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_data_sources_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_data_sources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_data_sources_id_seq OWNED BY report_data_sources.id;


--
-- Name: report_definitions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_definitions (
    report_id integer,
    definition text
);


--
-- Name: reports; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE reports (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    favicon_url character varying(255) DEFAULT ''::character varying NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    custom_sql text,
    checksum character varying(255),
    last_generated_at timestamp without time zone,
    total_row_count bigint DEFAULT 0 NOT NULL,
    has_row_matching boolean,
    time_range character varying(255) DEFAULT 'Last 30 Days'::character varying NOT NULL,
    user_id integer NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    edited_by_user_id integer NOT NULL,
    edited_at timestamp without time zone NOT NULL,
    viewed_at timestamp without time zone,
    runs_in_redshift boolean DEFAULT false NOT NULL,
    query_strategy character varying(255),
    always_rebuild boolean DEFAULT false NOT NULL
);


--
-- Name: scopes; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE scopes (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    schema_id integer NOT NULL,
    table_name character varying(255),
    has_data boolean DEFAULT false NOT NULL
);


--
-- Name: source_reports; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE source_reports (
    id integer NOT NULL,
    report_id integer NOT NULL,
    data_source_id integer NOT NULL,
    account_id integer NOT NULL,
    schema_id integer NOT NULL,
    data_source_scope_id integer
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE users (
    id integer NOT NULL,
    email character varying(255) DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying(255) DEFAULT ''::character varying NOT NULL,
    reset_password_token character varying(255),
    reset_password_sent_at timestamp without time zone,
    remember_created_at timestamp without time zone,
    sign_in_count integer DEFAULT 0,
    current_sign_in_at timestamp without time zone,
    last_sign_in_at timestamp without time zone,
    current_sign_in_ip character varying(255),
    last_sign_in_ip character varying(255),
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    name character varying(255) DEFAULT ''::character varying NOT NULL,
    title character varying(255) DEFAULT ''::character varying NOT NULL,
    phone character varying(255) DEFAULT ''::character varying NOT NULL,
    account_id integer NOT NULL,
    welcomed_at timestamp without time zone,
    demo boolean DEFAULT false NOT NULL,
    needs_setup boolean DEFAULT true NOT NULL,
    failed_attempts integer DEFAULT 0 NOT NULL,
    unlock_token character varying(255),
    locked_at timestamp without time zone,
    invited_by_user_id integer,
    role_id integer,
    account_admin boolean DEFAULT true NOT NULL,
    favorite_dashboard_id integer,
    billable boolean DEFAULT true NOT NULL,
    invitation_token character varying(255),
    invitation_created_at timestamp without time zone,
    invitation_sent_at timestamp without time zone,
    invitation_accepted_at timestamp without time zone,
    invitation_limit integer,
    invited_by_id integer,
    invited_by_type character varying(255),
    invitations_count integer DEFAULT 0,
    staq_admin boolean DEFAULT false
);


--
-- Name: report_dependencies; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW report_dependencies AS
 SELECT r.id AS report_id,
    r.name AS report_name,
        CASE ds.type
            WHEN 1 THEN 'connection'::text
            WHEN 2 THEN 'connection'::text
            WHEN 3 THEN 'source_report'::text
            WHEN 4 THEN 'custom_connection'::text
            ELSE NULL::text
        END AS data_source_type,
    COALESCE(pc.id, c.id, sr.id, cc.id) AS source_id,
    COALESCE(pc.name, c.name, srr.name, cc.name) AS source_name,
        CASE sc.name
            WHEN 'report'::text THEN NULL::character varying
            ELSE sc.name
        END AS scope
   FROM ((((((((((reports r
     JOIN report_data_sources rds ON ((r.id = rds.report_id)))
     JOIN scopes sc ON ((rds.scope_id = sc.id)))
     JOIN data_sources ds ON ((rds.data_source_id = ds.id)))
     LEFT JOIN users u ON ((r.user_id = u.id)))
     LEFT JOIN connections c ON (((ds.type = 1) AND (ds.id = c.data_source_id))))
     LEFT JOIN platforms p ON (((ds.type = 2) AND (ds.id = p.data_source_id))))
     LEFT JOIN connections pc ON ((((ds.type = 2) AND (p.id = pc.platform_id)) AND (u.account_id = pc.account_id))))
     LEFT JOIN source_reports sr ON (((ds.type = 3) AND (ds.id = sr.data_source_id))))
     LEFT JOIN reports srr ON (((ds.type = 3) AND (sr.report_id = srr.id))))
     LEFT JOIN custom_connections cc ON (((ds.type = 4) AND (ds.id = cc.data_source_id))))
  ORDER BY r.id;


--
-- Name: report_filters; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_filters (
    id integer NOT NULL,
    filter_type integer NOT NULL,
    comparator character varying(255) NOT NULL,
    operator character varying(255) NOT NULL,
    logical_operator character varying(255),
    "values" text[] DEFAULT '{}'::text[] NOT NULL
);


--
-- Name: report_filters_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_filters_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_filters_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_filters_id_seq OWNED BY report_filters.id;


--
-- Name: report_job_state_transitions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_job_state_transitions (
    id integer NOT NULL,
    report_job_id integer,
    event character varying(255),
    "from" character varying(255),
    "to" character varying(255),
    message text,
    backtrace text,
    created_at timestamp without time zone,
    sidekiq_job_id character varying(255),
    user_message text
);


--
-- Name: report_job_state_transitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_job_state_transitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_job_state_transitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_job_state_transitions_id_seq OWNED BY report_job_state_transitions.id;


--
-- Name: report_jobs; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_jobs (
    id integer NOT NULL,
    report_id integer NOT NULL,
    state character varying(255) DEFAULT 'new'::character varying NOT NULL,
    key character varying(255) DEFAULT 'NOTUSED'::character varying NOT NULL,
    sql text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    triggered_by character varying(255) NOT NULL,
    sources text,
    duration real DEFAULT 0.0 NOT NULL,
    backend_pid character varying(255),
    flags hstore,
    time_range_override character varying(255),
    row_count bigint DEFAULT 0 NOT NULL,
    size_on_disk bigint DEFAULT 0 NOT NULL
);


--
-- Name: report_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_jobs_id_seq OWNED BY report_jobs.id;


--
-- Name: report_tables_staq_advanced_query_1; Type: FOREIGN TABLE; Schema: public; Owner: -; Tablespace: 
--

/* FOREIGN DATA WRAPPER TABLE INFO NOT USEFUL IN DEVELOPMENT MODE */


--
-- Name: report_template_columns; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_template_columns (
    id integer NOT NULL,
    report_template_id integer NOT NULL,
    field_id integer NOT NULL,
    label character varying(255) NOT NULL,
    type character varying(255) NOT NULL,
    column_type character varying(255) NOT NULL,
    style character varying(255),
    hide boolean DEFAULT false NOT NULL,
    "default" character varying(255),
    sort_direction character varying(255),
    sort_priority integer,
    summarization text,
    total character varying(255),
    display_order integer,
    steps text,
    is_unique_key boolean DEFAULT false NOT NULL,
    "precision" integer DEFAULT 0 NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: report_template_columns_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_template_columns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_template_columns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_template_columns_id_seq OWNED BY report_template_columns.id;


--
-- Name: report_templates; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_templates (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    favicon_url character varying(255),
    time_range character varying(255),
    staq_notes text DEFAULT ''::text NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    active boolean DEFAULT true NOT NULL
);


--
-- Name: report_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_templates_id_seq OWNED BY report_templates.id;


--
-- Name: report_users; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_users (
    id integer NOT NULL,
    report_id integer NOT NULL,
    user_id integer NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    sharer_user_id integer,
    shared_with character varying(255) DEFAULT ''::character varying NOT NULL
);


--
-- Name: report_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_users_id_seq OWNED BY report_users.id;


--
-- Name: report_view_database_accounts; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_view_database_accounts (
    id integer NOT NULL,
    report_view_database_id integer NOT NULL,
    account_id integer NOT NULL
);


--
-- Name: report_view_database_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_view_database_accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_view_database_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_view_database_accounts_id_seq OWNED BY report_view_database_accounts.id;


--
-- Name: report_view_databases; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_view_databases (
    id integer NOT NULL,
    instance_name character varying(255) NOT NULL,
    alias_name character varying(255) NOT NULL,
    default_database boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: report_view_databases_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_view_databases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_view_databases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_view_databases_id_seq OWNED BY report_view_databases.id;


--
-- Name: report_view_users; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_view_users (
    id integer NOT NULL,
    report_view_id integer NOT NULL,
    user_id integer NOT NULL,
    sharer_user_id integer,
    follower boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: report_view_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_view_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_view_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_view_users_id_seq OWNED BY report_view_users.id;


--
-- Name: report_views; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE report_views (
    id integer NOT NULL,
    report_id integer NOT NULL,
    user_id integer NOT NULL,
    parent_report_view_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    filters text DEFAULT '--- []
'::text NOT NULL
);


--
-- Name: report_views_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE report_views_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_views_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE report_views_id_seq OWNED BY report_views.id;


--
-- Name: reports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE reports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE reports_id_seq OWNED BY reports.id;


--
-- Name: role_permitted_operations; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE role_permitted_operations (
    id integer NOT NULL,
    role_id integer NOT NULL,
    protected_operation_id integer NOT NULL
);


--
-- Name: role_permitted_operations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE role_permitted_operations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: role_permitted_operations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE role_permitted_operations_id_seq OWNED BY role_permitted_operations.id;


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE roles (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE roles_id_seq OWNED BY roles.id;


--
-- Name: schema_changes; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE schema_changes (
    id integer NOT NULL,
    target_id integer NOT NULL,
    target_type character varying(255) NOT NULL,
    requested_by_id integer NOT NULL,
    requested_by_type character varying(255) NOT NULL,
    action character varying(255) NOT NULL,
    options hstore,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    message text,
    state character varying(255) DEFAULT 'new'::character varying NOT NULL,
    jid character varying(255)
);


--
-- Name: schema_changes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE schema_changes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: schema_changes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE schema_changes_id_seq OWNED BY schema_changes.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE schema_migrations (
    version character varying(255) NOT NULL
);


--
-- Name: schemas; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE schemas (
    id integer NOT NULL,
    type integer NOT NULL
);


--
-- Name: schemas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE schemas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: schemas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE schemas_id_seq OWNED BY schemas.id;


--
-- Name: scopes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE scopes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: scopes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE scopes_id_seq OWNED BY scopes.id;


--
-- Name: source_report_dependencies; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW source_report_dependencies AS
 SELECT s.id AS source_report_id,
    d.report_id,
    d.report_name,
    d.data_source_type,
    d.source_id,
    d.source_name,
    d.scope
   FROM (source_reports s
     JOIN report_dependencies d ON ((s.report_id = d.report_id)))
  ORDER BY s.id;


--
-- Name: source_reports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE source_reports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: source_reports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE source_reports_id_seq OWNED BY source_reports.id;


--
-- Name: stale_connections; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW stale_connections AS
 WITH recent_successes AS (
         SELECT c.id
           FROM connections c,
            collection_missions cm
          WHERE (((cm.connection_id = c.id) AND ((cm.connection_type)::text = 'Connection'::text)) AND ((cm.state)::text = 'success'::text))
          GROUP BY c.id
         HAVING ((now() - max((cm.mission_end_at)::timestamp with time zone)) <= '24:00:00'::interval hour)
        ), scheduled_later AS (
         SELECT c.id
           FROM connections c,
            collection_missions cm
          WHERE ((((cm.connection_id = c.id) AND ((cm.connection_type)::text = 'Connection'::text)) AND ((cm.state)::text = 'new'::text)) AND (cm.scheduled_at >= now()))
          GROUP BY c.id
        ), recent_successes_for_scheduled AS (
         SELECT c.id
           FROM connections c,
            collection_missions cm
          WHERE ((((cm.connection_id = c.id) AND ((cm.connection_type)::text = 'Connection'::text)) AND ((cm.state)::text = 'success'::text)) AND (c.id IN ( SELECT scheduled_later.id
                   FROM scheduled_later)))
          GROUP BY c.id
         HAVING ((now() - max((cm.mission_end_at)::timestamp with time zone)) <= '48:00:00'::interval hour)
        )
 SELECT c.id,
    c.name,
    c.platform_id,
    c.account_id,
    c.state
   FROM platforms p,
    accounts a,
    extractors e,
    (connections c
     LEFT JOIN collection_missions cm ON ((c.id = cm.connection_id)))
  WHERE ((((((((((cm.connection_type)::text = 'Connection'::text) AND (NOT (c.id IN ( SELECT recent_successes.id
           FROM recent_successes)))) AND (NOT (c.id IN ( SELECT recent_successes_for_scheduled.id
           FROM recent_successes_for_scheduled)))) AND (c.platform_id = p.id)) AND (c.account_id = a.id)) AND (p.extractor_id = e.id)) AND (e.available IS TRUE)) AND ((c.state)::text <> 'Unavailable'::text)) AND (a.active IS TRUE))
  GROUP BY c.id, c.name, c.platform_id, c.account_id, c.state
UNION
 SELECT c.id,
    c.name,
    c.platform_id,
    c.account_id,
    c.state
   FROM platforms p,
    accounts a,
    extractors e,
    (connections c
     LEFT JOIN collection_missions cm ON ((c.id = cm.connection_id)))
  WHERE (((((((cm.connection_id IS NULL) AND (c.platform_id = p.id)) AND (c.account_id = a.id)) AND (p.extractor_id = e.id)) AND (e.available IS TRUE)) AND ((c.state)::text <> 'Unavailable'::text)) AND (a.active IS TRUE))
  GROUP BY c.id, c.name, c.platform_id, c.account_id, c.state
  ORDER BY 3, 4;


--
-- Name: stale_custom_connections; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW stale_custom_connections AS
 WITH recent_successes AS (
         SELECT cc.id
           FROM custom_connections cc,
            collection_missions cm
          WHERE (((cm.connection_id = cc.id) AND ((cm.connection_type)::text = 'CustomConnection'::text)) AND ((cm.state)::text = 'success'::text))
          GROUP BY cc.id
         HAVING ((now() - (max(cm.mission_end_at))::timestamp with time zone) <= '24:00:00'::interval hour)
        ), scheduled_later AS (
         SELECT cc.id
           FROM custom_connections cc,
            collection_missions cm
          WHERE ((((cm.connection_id = cc.id) AND ((cm.connection_type)::text = 'CustomConnection'::text)) AND ((cm.state)::text = 'new'::text)) AND (cm.scheduled_at >= now()))
          GROUP BY cc.id
        ), recent_successes_for_scheduled AS (
         SELECT cc.id
           FROM custom_connections cc,
            collection_missions cm
          WHERE ((((cm.connection_id = cc.id) AND ((cm.connection_type)::text = 'CustomConnection'::text)) AND ((cm.state)::text = 'success'::text)) AND (cc.id IN ( SELECT scheduled_later.id
                   FROM scheduled_later)))
          GROUP BY cc.id
         HAVING ((now() - (max(cm.mission_end_at))::timestamp with time zone) <= '48:00:00'::interval hour)
        )
 SELECT cc.id,
    cc.name,
    cc.account_id,
    cc.state
   FROM accounts a,
    (custom_connections cc
     LEFT JOIN collection_missions cm ON ((cm.connection_id = cc.id)))
  WHERE ((((((((cm.connection_type)::text = 'CustomConnection'::text) AND (NOT (cc.id IN ( SELECT recent_successes.id
           FROM recent_successes)))) AND (NOT (cc.id IN ( SELECT recent_successes_for_scheduled.id
           FROM recent_successes_for_scheduled)))) AND (cc.account_id = a.id)) AND ((cc.state)::text <> 'Unavailable'::text)) AND ((cc.extraction_engine_type)::text <> ALL (ARRAY['UploadedFile'::text, 'InboundEmail'::text]))) AND (a.active IS TRUE))
  GROUP BY cc.id, cc.name, cc.account_id, cc.state
UNION
 SELECT cc.id,
    cc.name,
    cc.account_id,
    cc.state
   FROM accounts a,
    (custom_connections cc
     LEFT JOIN collection_missions cm ON ((cc.id = cm.connection_id)))
  WHERE (((((cm.connection_id IS NULL) AND (cc.account_id = a.id)) AND ((cc.state)::text <> 'Unavailable'::text)) AND ((cc.extraction_engine_type)::text <> ALL (ARRAY['UploadedFile'::text, 'InboundEmail'::text]))) AND (a.active IS TRUE))
  GROUP BY cc.id, cc.name, cc.account_id, cc.state
  ORDER BY 2, 3;


--
-- Name: stale_reports; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW stale_reports AS
 SELECT r.id,
    r.name,
    r.created_at,
    r.updated_at,
    r.last_generated_at,
    r.total_row_count,
    date_part('day'::text, age(now(), (r.last_generated_at)::timestamp with time zone)) AS last_generated_at_days_ago
   FROM (((reports r
     JOIN report_users ru ON ((r.id = ru.report_id)))
     JOIN users u ON ((ru.user_id = u.id)))
     JOIN accounts a ON ((u.account_id = a.id)))
  WHERE (((a.active IS TRUE) AND (r.last_generated_at IS NOT NULL)) AND (age(now(), (r.last_generated_at)::timestamp with time zone) > '12:00:00'::interval))
  ORDER BY date_part('day'::text, age(now(), (r.last_generated_at)::timestamp with time zone)) DESC;


--
-- Name: staq_events; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE staq_events (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    triggered_by character varying(255) NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    processed_at timestamp without time zone,
    data hstore,
    table_name character varying(255),
    table_operation character varying(255),
    table_record_id integer
);


--
-- Name: staq_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE staq_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: staq_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE staq_events_id_seq OWNED BY staq_events.id;


--
-- Name: temporal_report_jobs; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE temporal_report_jobs (
    id integer NOT NULL,
    user_id integer NOT NULL,
    created_from_report_id integer,
    definition text NOT NULL,
    state character varying(255) DEFAULT 'new'::character varying NOT NULL,
    sql text,
    message text,
    backtrace text,
    user_message text,
    flags hstore,
    triggered_by character varying(255) NOT NULL,
    sources text,
    duration real DEFAULT 0.0 NOT NULL,
    backend_pid character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    data_source_id integer,
    scope_id integer,
    time_range_override character varying(255),
    row_count bigint DEFAULT 0 NOT NULL,
    size_on_disk bigint DEFAULT 0 NOT NULL
);


--
-- Name: subscription_categories; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE subscription_categories (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    label character varying(255) DEFAULT ''::character varying,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: subscription_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE subscription_categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscription_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE subscription_categories_id_seq OWNED BY subscription_categories.id;


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE subscriptions (
    id integer NOT NULL,
    subscription_category_id integer NOT NULL,
    description text NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    name character varying(255) DEFAULT ''::character varying NOT NULL,
    email_template_id integer NOT NULL,
    visible boolean DEFAULT true NOT NULL
);


--
-- Name: subscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE subscriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE subscriptions_id_seq OWNED BY subscriptions.id;


--
-- Name: support_requests; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE support_requests (
    id integer NOT NULL,
    user_id integer NOT NULL,
    classification character varying(255) NOT NULL,
    description text NOT NULL,
    state character varying(255) DEFAULT 'new'::character varying NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    CONSTRAINT support_requests_state_whitelist CHECK (((state)::text = ANY (ARRAY[('new'::character varying)::text, ('addressing'::character varying)::text, ('satisfied'::character varying)::text])))
);


--
-- Name: support_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE support_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: support_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE support_requests_id_seq OWNED BY support_requests.id;


--
-- Name: tag_location_categories; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE tag_location_categories (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    CONSTRAINT tag_location_categories_name_present CHECK ((length(btrim((name)::text)) > 0))
);


--
-- Name: tag_location_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE tag_location_categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tag_location_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE tag_location_categories_id_seq OWNED BY tag_location_categories.id;


--
-- Name: tag_locations; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE tag_locations (
    id integer NOT NULL,
    tag_location_category_id integer NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    location character varying(255) NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    CONSTRAINT tag_locations_location_present CHECK ((length(btrim((location)::text)) > 0))
);


--
-- Name: tag_locations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE tag_locations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tag_locations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE tag_locations_id_seq OWNED BY tag_locations.id;


--
-- Name: tag_matchers; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE tag_matchers (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    regex text,
    options integer DEFAULT 0 NOT NULL,
    handler text,
    sample text DEFAULT ''::text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    CONSTRAINT tag_matchers_handler_present CHECK ((length(btrim(handler)) > 0)),
    CONSTRAINT tag_matchers_regex_present CHECK ((length(btrim(regex)) > 0))
);


--
-- Name: tag_matchers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE tag_matchers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tag_matchers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE tag_matchers_id_seq OWNED BY tag_matchers.id;


--
-- Name: taggings; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE taggings (
    id integer NOT NULL,
    tag_id integer NOT NULL,
    taggable_id integer NOT NULL,
    taggable_type character varying(255) NOT NULL,
    tagger_id integer,
    tagger_type character varying(255),
    context character varying(128),
    created_at timestamp without time zone
);


--
-- Name: taggings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE taggings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: taggings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE taggings_id_seq OWNED BY taggings.id;


--
-- Name: tags; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE tags (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    taggings_count integer DEFAULT 0 NOT NULL,
    "integer" integer DEFAULT 0 NOT NULL,
    CONSTRAINT tags_name_present CHECK ((length(btrim((name)::text)) > 0))
);


--
-- Name: tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE tags_id_seq OWNED BY tags.id;


--
-- Name: temporal_report_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE temporal_report_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: temporal_report_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE temporal_report_jobs_id_seq OWNED BY temporal_report_jobs.id;


--
-- Name: uploaded_files; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE uploaded_files (
    id integer NOT NULL,
    filename character varying(255) DEFAULT ''::character varying NOT NULL,
    custom_connection_id integer NOT NULL,
    url text NOT NULL,
    uploaded_by character varying(255) NOT NULL,
    size character varying(255) DEFAULT '0'::character varying NOT NULL,
    mimetype character varying(255),
    location character varying(255),
    container character varying(255),
    key character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    CONSTRAINT uploaded_files_url_present CHECK ((length(btrim(url)) > 0))
);


--
-- Name: uploaded_files_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE uploaded_files_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: uploaded_files_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE uploaded_files_id_seq OWNED BY uploaded_files.id;


--
-- Name: user_subscriptions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE user_subscriptions (
    id integer NOT NULL,
    user_id integer NOT NULL,
    subscription_id integer NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: user_subscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE user_subscriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_subscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE user_subscriptions_id_seq OWNED BY user_subscriptions.id;


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE users_id_seq OWNED BY users.id;


--
-- Name: versions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE versions (
    id integer NOT NULL,
    item_type character varying(255) NOT NULL,
    item_id integer NOT NULL,
    event character varying(255) NOT NULL,
    whodunnit character varying(255),
    object text,
    created_at timestamp without time zone,
    object_changes text,
    transaction_id integer
);


--
-- Name: versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE versions_id_seq OWNED BY versions.id;


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY account_domains ALTER COLUMN id SET DEFAULT nextval('account_domains_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY account_state_transitions ALTER COLUMN id SET DEFAULT nextval('account_state_transitions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY account_tokens ALTER COLUMN id SET DEFAULT nextval('account_tokens_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY accounts ALTER COLUMN id SET DEFAULT nextval('accounts_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY accounts_admins ALTER COLUMN id SET DEFAULT nextval('accounts_admins_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY admins ALTER COLUMN id SET DEFAULT nextval('admins_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY announcements ALTER COLUMN id SET DEFAULT nextval('announcements_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY applets ALTER COLUMN id SET DEFAULT nextval('applets_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY applications ALTER COLUMN id SET DEFAULT nextval('applications_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY categories ALTER COLUMN id SET DEFAULT nextval('categories_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY collection_mission_state_transitions ALTER COLUMN id SET DEFAULT nextval('collection_mission_state_transitions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY collection_mission_tasks ALTER COLUMN id SET DEFAULT nextval('new_collection_mission_tasks_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY collection_missions ALTER COLUMN id SET DEFAULT nextval('collection_missions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY configurations ALTER COLUMN id SET DEFAULT nextval('configurations_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY connection_issues ALTER COLUMN id SET DEFAULT nextval('connection_issues_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY connection_semaphores ALTER COLUMN id SET DEFAULT nextval('connection_semaphores_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY connections ALTER COLUMN id SET DEFAULT nextval('connections_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY control_mission_state_transitions ALTER COLUMN id SET DEFAULT nextval('control_mission_state_transitions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY control_mission_tasks ALTER COLUMN id SET DEFAULT nextval('control_mission_tasks_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY control_missions ALTER COLUMN id SET DEFAULT nextval('control_missions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY cube_match_dimensions ALTER COLUMN id SET DEFAULT nextval('cube_match_dimensions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY cube_match_values ALTER COLUMN id SET DEFAULT nextval('cube_match_values_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY cube_matches ALTER COLUMN id SET DEFAULT nextval('cube_matches_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY cube_rules ALTER COLUMN id SET DEFAULT nextval('cube_rules_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY cubes ALTER COLUMN id SET DEFAULT nextval('cubes_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY custom_connection_issues ALTER COLUMN id SET DEFAULT nextval('custom_connection_issues_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY custom_connections ALTER COLUMN id SET DEFAULT nextval('custom_connections_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY custom_fields ALTER COLUMN id SET DEFAULT nextval('custom_fields_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY customer_favicons ALTER COLUMN id SET DEFAULT nextval('customer_favicons_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY customer_logos ALTER COLUMN id SET DEFAULT nextval('customer_logos_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY customers ALTER COLUMN id SET DEFAULT nextval('customers_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_users ALTER COLUMN id SET DEFAULT nextval('dashboard_users_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboards ALTER COLUMN id SET DEFAULT nextval('dashboards_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY data_source_fields ALTER COLUMN id SET DEFAULT nextval('data_source_fields_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY data_source_scopes ALTER COLUMN id SET DEFAULT nextval('data_source_scopes_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY data_sources ALTER COLUMN id SET DEFAULT nextval('data_sources_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY email_layouts ALTER COLUMN id SET DEFAULT nextval('email_layouts_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY email_templates ALTER COLUMN id SET DEFAULT nextval('email_templates_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY extraction_engines ALTER COLUMN id SET DEFAULT nextval('extraction_engines_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY extraction_scheduling_recipes ALTER COLUMN id SET DEFAULT nextval('extraction_scheduling_recipes_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY extractor_assets ALTER COLUMN id SET DEFAULT nextval('extractor_assets_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY extractor_issues ALTER COLUMN id SET DEFAULT nextval('extractor_issues_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY extractor_rate_limits ALTER COLUMN id SET DEFAULT nextval('extractor_rate_limits_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY extractor_semaphores ALTER COLUMN id SET DEFAULT nextval('extractor_semaphores_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY extractor_time_zone_specifications ALTER COLUMN id SET DEFAULT nextval('extractor_time_zone_specifications_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY extractors ALTER COLUMN id SET DEFAULT nextval('extractors_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY feature_flags ALTER COLUMN id SET DEFAULT nextval('feature_flags_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY fields ALTER COLUMN id SET DEFAULT nextval('fields_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY inbound_email_addresses ALTER COLUMN id SET DEFAULT nextval('inbound_email_addresses_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY inbound_email_attachments ALTER COLUMN id SET DEFAULT nextval('inbound_email_attachments_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY inbound_email_messages ALTER COLUMN id SET DEFAULT nextval('inbound_email_messages_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY inbound_files ALTER COLUMN id SET DEFAULT nextval('inbound_files_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY inbound_google_files ALTER COLUMN id SET DEFAULT nextval('inbound_google_files_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY installed_report_applications ALTER COLUMN id SET DEFAULT nextval('installed_report_applications_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY issues ALTER COLUMN id SET DEFAULT nextval('issues_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY line_items ALTER COLUMN id SET DEFAULT nextval('line_items_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY loaded_tables ALTER COLUMN id SET DEFAULT nextval('loaded_tables_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY notification_deliveries ALTER COLUMN id SET DEFAULT nextval('notification_deliveries_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY notification_delivery_state_transitions ALTER COLUMN id SET DEFAULT nextval('notification_delivery_state_transitions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY notifications ALTER COLUMN id SET DEFAULT nextval('notifications_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY orders ALTER COLUMN id SET DEFAULT nextval('orders_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY param_templates ALTER COLUMN id SET DEFAULT nextval('param_templates_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY password_resets ALTER COLUMN id SET DEFAULT nextval('password_resets_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY plan_categories ALTER COLUMN id SET DEFAULT nextval('plan_categories_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY platform_categories ALTER COLUMN id SET DEFAULT nextval('platform_categories_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY platforms ALTER COLUMN id SET DEFAULT nextval('platforms_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY products ALTER COLUMN id SET DEFAULT nextval('products_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY protected_operations ALTER COLUMN id SET DEFAULT nextval('protected_operations_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY rails_admin_histories ALTER COLUMN id SET DEFAULT nextval('rails_admin_histories_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_column_def_backups ALTER COLUMN id SET DEFAULT nextval('report_column_def_backups_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_column_fields ALTER COLUMN id SET DEFAULT nextval('report_column_fields_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_column_filters ALTER COLUMN id SET DEFAULT nextval('report_column_filters_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_columns ALTER COLUMN id SET DEFAULT nextval('report_columns_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_comments ALTER COLUMN id SET DEFAULT nextval('report_comments_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_custom_fields ALTER COLUMN id SET DEFAULT nextval('report_custom_fields_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_data_source_filters ALTER COLUMN id SET DEFAULT nextval('report_data_source_filters_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_data_sources ALTER COLUMN id SET DEFAULT nextval('report_data_sources_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_filters ALTER COLUMN id SET DEFAULT nextval('report_filters_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_job_state_transitions ALTER COLUMN id SET DEFAULT nextval('report_job_state_transitions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_jobs ALTER COLUMN id SET DEFAULT nextval('report_jobs_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_template_columns ALTER COLUMN id SET DEFAULT nextval('report_template_columns_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_templates ALTER COLUMN id SET DEFAULT nextval('report_templates_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_users ALTER COLUMN id SET DEFAULT nextval('report_users_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_view_database_accounts ALTER COLUMN id SET DEFAULT nextval('report_view_database_accounts_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_view_databases ALTER COLUMN id SET DEFAULT nextval('report_view_databases_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_view_users ALTER COLUMN id SET DEFAULT nextval('report_view_users_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_views ALTER COLUMN id SET DEFAULT nextval('report_views_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports ALTER COLUMN id SET DEFAULT nextval('reports_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY role_permitted_operations ALTER COLUMN id SET DEFAULT nextval('role_permitted_operations_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY roles ALTER COLUMN id SET DEFAULT nextval('roles_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY schema_changes ALTER COLUMN id SET DEFAULT nextval('schema_changes_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY schemas ALTER COLUMN id SET DEFAULT nextval('schemas_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY scopes ALTER COLUMN id SET DEFAULT nextval('scopes_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY source_reports ALTER COLUMN id SET DEFAULT nextval('source_reports_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY staq_events ALTER COLUMN id SET DEFAULT nextval('staq_events_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY subscription_categories ALTER COLUMN id SET DEFAULT nextval('subscription_categories_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY subscriptions ALTER COLUMN id SET DEFAULT nextval('subscriptions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY support_requests ALTER COLUMN id SET DEFAULT nextval('support_requests_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY tag_location_categories ALTER COLUMN id SET DEFAULT nextval('tag_location_categories_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY tag_locations ALTER COLUMN id SET DEFAULT nextval('tag_locations_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY tag_matchers ALTER COLUMN id SET DEFAULT nextval('tag_matchers_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY taggings ALTER COLUMN id SET DEFAULT nextval('taggings_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY tags ALTER COLUMN id SET DEFAULT nextval('tags_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY temporal_report_jobs ALTER COLUMN id SET DEFAULT nextval('temporal_report_jobs_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY uploaded_files ALTER COLUMN id SET DEFAULT nextval('uploaded_files_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY user_subscriptions ALTER COLUMN id SET DEFAULT nextval('user_subscriptions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY users ALTER COLUMN id SET DEFAULT nextval('users_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY versions ALTER COLUMN id SET DEFAULT nextval('versions_id_seq'::regclass);


--
-- Name: account_domains_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY account_domains
    ADD CONSTRAINT account_domains_pkey PRIMARY KEY (id);


--
-- Name: account_state_transitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY account_state_transitions
    ADD CONSTRAINT account_state_transitions_pkey PRIMARY KEY (id);


--
-- Name: account_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY account_tokens
    ADD CONSTRAINT account_tokens_pkey PRIMARY KEY (id);


--
-- Name: accounts_admins_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY accounts_admins
    ADD CONSTRAINT accounts_admins_pkey PRIMARY KEY (id);


--
-- Name: accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: admins_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY admins
    ADD CONSTRAINT admins_pkey PRIMARY KEY (id);


--
-- Name: announcements_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY announcements
    ADD CONSTRAINT announcements_pkey PRIMARY KEY (id);


--
-- Name: applets_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY applets
    ADD CONSTRAINT applets_pkey PRIMARY KEY (id);


--
-- Name: applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY applications
    ADD CONSTRAINT applications_pkey PRIMARY KEY (id);


--
-- Name: authentication_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY authentication_tokens
    ADD CONSTRAINT authentication_tokens_pkey PRIMARY KEY (id);


--
-- Name: categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: collection_mission_state_transitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY collection_mission_state_transitions
    ADD CONSTRAINT collection_mission_state_transitions_pkey PRIMARY KEY (id);


--
-- Name: collection_missions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY collection_missions
    ADD CONSTRAINT collection_missions_pkey PRIMARY KEY (id);


--
-- Name: configurations_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY configurations
    ADD CONSTRAINT configurations_pkey PRIMARY KEY (id);


--
-- Name: connection_issues_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY connection_issues
    ADD CONSTRAINT connection_issues_pkey PRIMARY KEY (id);


--
-- Name: connection_semaphores_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY connection_semaphores
    ADD CONSTRAINT connection_semaphores_pkey PRIMARY KEY (id);


--
-- Name: control_mission_state_transitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY control_mission_state_transitions
    ADD CONSTRAINT control_mission_state_transitions_pkey PRIMARY KEY (id);


--
-- Name: control_mission_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY control_mission_tasks
    ADD CONSTRAINT control_mission_tasks_pkey PRIMARY KEY (id);


--
-- Name: control_missions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY control_missions
    ADD CONSTRAINT control_missions_pkey PRIMARY KEY (id);


--
-- Name: cube_match_dimensions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY cube_match_dimensions
    ADD CONSTRAINT cube_match_dimensions_pkey PRIMARY KEY (id);


--
-- Name: cube_match_values_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY cube_match_values
    ADD CONSTRAINT cube_match_values_pkey PRIMARY KEY (id);


--
-- Name: cube_matches_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY cube_matches
    ADD CONSTRAINT cube_matches_pkey PRIMARY KEY (id);


--
-- Name: cube_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY cube_rules
    ADD CONSTRAINT cube_rules_pkey PRIMARY KEY (id);


--
-- Name: cubes_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY cubes
    ADD CONSTRAINT cubes_pkey PRIMARY KEY (id);


--
-- Name: custom_connection_issues_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY custom_connection_issues
    ADD CONSTRAINT custom_connection_issues_pkey PRIMARY KEY (id);


--
-- Name: custom_connections_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY custom_connections
    ADD CONSTRAINT custom_connections_pkey PRIMARY KEY (id);


--
-- Name: custom_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY custom_fields
    ADD CONSTRAINT custom_fields_pkey PRIMARY KEY (id);


--
-- Name: customer_favicons_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY customer_favicons
    ADD CONSTRAINT customer_favicons_pkey PRIMARY KEY (id);


--
-- Name: customer_logos_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY customer_logos
    ADD CONSTRAINT customer_logos_pkey PRIMARY KEY (id);


--
-- Name: customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: dashboard_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY dashboard_users
    ADD CONSTRAINT dashboard_users_pkey PRIMARY KEY (id);


--
-- Name: dashboards_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY dashboards
    ADD CONSTRAINT dashboards_pkey PRIMARY KEY (id);


--
-- Name: data_source_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY data_source_fields
    ADD CONSTRAINT data_source_fields_pkey PRIMARY KEY (id);


--
-- Name: data_source_scopes_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY data_source_scopes
    ADD CONSTRAINT data_source_scopes_pkey PRIMARY KEY (id);


--
-- Name: data_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY data_sources
    ADD CONSTRAINT data_sources_pkey PRIMARY KEY (id);


--
-- Name: email_layouts_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY email_layouts
    ADD CONSTRAINT email_layouts_pkey PRIMARY KEY (id);


--
-- Name: email_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY email_templates
    ADD CONSTRAINT email_templates_pkey PRIMARY KEY (id);


--
-- Name: extraction_engines_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY extraction_engines
    ADD CONSTRAINT extraction_engines_pkey PRIMARY KEY (id);


--
-- Name: extraction_scheduling_recipes_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY extraction_scheduling_recipes
    ADD CONSTRAINT extraction_scheduling_recipes_pkey PRIMARY KEY (id);


--
-- Name: extraction_scripts_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY extractors
    ADD CONSTRAINT extraction_scripts_pkey PRIMARY KEY (id);


--
-- Name: extractor_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY extractor_assets
    ADD CONSTRAINT extractor_assets_pkey PRIMARY KEY (id);


--
-- Name: extractor_issues_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY extractor_issues
    ADD CONSTRAINT extractor_issues_pkey PRIMARY KEY (id);


--
-- Name: extractor_rate_limits_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY extractor_rate_limits
    ADD CONSTRAINT extractor_rate_limits_pkey PRIMARY KEY (id);


--
-- Name: extractor_semaphores_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY extractor_semaphores
    ADD CONSTRAINT extractor_semaphores_pkey PRIMARY KEY (id);


--
-- Name: extractor_time_zone_specifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY extractor_time_zone_specifications
    ADD CONSTRAINT extractor_time_zone_specifications_pkey PRIMARY KEY (id);


--
-- Name: feature_flags_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY feature_flags
    ADD CONSTRAINT feature_flags_pkey PRIMARY KEY (id);


--
-- Name: fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY fields
    ADD CONSTRAINT fields_pkey PRIMARY KEY (id);


--
-- Name: inbound_email_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY inbound_email_addresses
    ADD CONSTRAINT inbound_email_addresses_pkey PRIMARY KEY (id);


--
-- Name: inbound_email_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY inbound_email_attachments
    ADD CONSTRAINT inbound_email_attachments_pkey PRIMARY KEY (id);


--
-- Name: inbound_email_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY inbound_email_messages
    ADD CONSTRAINT inbound_email_messages_pkey PRIMARY KEY (id);


--
-- Name: inbound_files_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY inbound_files
    ADD CONSTRAINT inbound_files_pkey PRIMARY KEY (id);


--
-- Name: inbound_google_files_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY inbound_google_files
    ADD CONSTRAINT inbound_google_files_pkey PRIMARY KEY (id);


--
-- Name: installed_applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY installed_report_applications
    ADD CONSTRAINT installed_applications_pkey PRIMARY KEY (id);


--
-- Name: issues_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY issues
    ADD CONSTRAINT issues_pkey PRIMARY KEY (id);


--
-- Name: line_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY line_items
    ADD CONSTRAINT line_items_pkey PRIMARY KEY (id);


--
-- Name: loaded_tables_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY loaded_tables
    ADD CONSTRAINT loaded_tables_pkey PRIMARY KEY (id);


--
-- Name: new_collection_mission_tasks_pkey1; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY collection_mission_tasks
    ADD CONSTRAINT new_collection_mission_tasks_pkey1 PRIMARY KEY (id);


--
-- Name: notification_deliveries_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY notification_deliveries
    ADD CONSTRAINT notification_deliveries_pkey PRIMARY KEY (id);


--
-- Name: notification_delivery_state_transitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY notification_delivery_state_transitions
    ADD CONSTRAINT notification_delivery_state_transitions_pkey PRIMARY KEY (id);


--
-- Name: notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: param_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY param_templates
    ADD CONSTRAINT param_templates_pkey PRIMARY KEY (id);


--
-- Name: password_resets_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY password_resets
    ADD CONSTRAINT password_resets_pkey PRIMARY KEY (id);


--
-- Name: plan_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY plan_categories
    ADD CONSTRAINT plan_categories_pkey PRIMARY KEY (id);


--
-- Name: platform_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY platforms
    ADD CONSTRAINT platform_templates_pkey PRIMARY KEY (id);


--
-- Name: platforms_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY connections
    ADD CONSTRAINT platforms_pkey PRIMARY KEY (id);


--
-- Name: products_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: protected_operations_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY protected_operations
    ADD CONSTRAINT protected_operations_pkey PRIMARY KEY (id);


--
-- Name: provider_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY platform_categories
    ADD CONSTRAINT provider_categories_pkey PRIMARY KEY (id);


--
-- Name: rails_admin_histories_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY rails_admin_histories
    ADD CONSTRAINT rails_admin_histories_pkey PRIMARY KEY (id);


--
-- Name: report_column_def_backups_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_column_def_backups
    ADD CONSTRAINT report_column_def_backups_pkey PRIMARY KEY (id);


--
-- Name: report_column_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_column_fields
    ADD CONSTRAINT report_column_fields_pkey PRIMARY KEY (id);


--
-- Name: report_column_filters_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_column_filters
    ADD CONSTRAINT report_column_filters_pkey PRIMARY KEY (id);


--
-- Name: report_columns_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_columns
    ADD CONSTRAINT report_columns_pkey PRIMARY KEY (id);


--
-- Name: report_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_comments
    ADD CONSTRAINT report_comments_pkey PRIMARY KEY (id);


--
-- Name: report_custom_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_custom_fields
    ADD CONSTRAINT report_custom_fields_pkey PRIMARY KEY (id);


--
-- Name: report_data_source_filters_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_data_source_filters
    ADD CONSTRAINT report_data_source_filters_pkey PRIMARY KEY (id);


--
-- Name: report_data_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_data_sources
    ADD CONSTRAINT report_data_sources_pkey PRIMARY KEY (id);


--
-- Name: report_filters_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_filters
    ADD CONSTRAINT report_filters_pkey PRIMARY KEY (id);


--
-- Name: report_job_state_transitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_job_state_transitions
    ADD CONSTRAINT report_job_state_transitions_pkey PRIMARY KEY (id);


--
-- Name: report_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_jobs
    ADD CONSTRAINT report_jobs_pkey PRIMARY KEY (id);


--
-- Name: report_template_columns_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_template_columns
    ADD CONSTRAINT report_template_columns_pkey PRIMARY KEY (id);


--
-- Name: report_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_templates
    ADD CONSTRAINT report_templates_pkey PRIMARY KEY (id);


--
-- Name: report_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_users
    ADD CONSTRAINT report_users_pkey PRIMARY KEY (id);


--
-- Name: report_view_database_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_view_database_accounts
    ADD CONSTRAINT report_view_database_accounts_pkey PRIMARY KEY (id);


--
-- Name: report_view_databases_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_view_databases
    ADD CONSTRAINT report_view_databases_pkey PRIMARY KEY (id);


--
-- Name: report_view_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_view_users
    ADD CONSTRAINT report_view_users_pkey PRIMARY KEY (id);


--
-- Name: report_views_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY report_views
    ADD CONSTRAINT report_views_pkey PRIMARY KEY (id);


--
-- Name: reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY reports
    ADD CONSTRAINT reports_pkey PRIMARY KEY (id);


--
-- Name: role_permitted_operations_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY role_permitted_operations
    ADD CONSTRAINT role_permitted_operations_pkey PRIMARY KEY (id);


--
-- Name: roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: schema_changes_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY schema_changes
    ADD CONSTRAINT schema_changes_pkey PRIMARY KEY (id);


--
-- Name: schemas_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY schemas
    ADD CONSTRAINT schemas_pkey PRIMARY KEY (id);


--
-- Name: scopes_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY scopes
    ADD CONSTRAINT scopes_pkey PRIMARY KEY (id);


--
-- Name: source_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY source_reports
    ADD CONSTRAINT source_reports_pkey PRIMARY KEY (id);


--
-- Name: staq_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY staq_events
    ADD CONSTRAINT staq_events_pkey PRIMARY KEY (id);


--
-- Name: subscription_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY subscription_categories
    ADD CONSTRAINT subscription_categories_pkey PRIMARY KEY (id);


--
-- Name: subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: support_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY support_requests
    ADD CONSTRAINT support_requests_pkey PRIMARY KEY (id);


--
-- Name: tag_location_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY tag_location_categories
    ADD CONSTRAINT tag_location_categories_pkey PRIMARY KEY (id);


--
-- Name: tag_locations_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY tag_locations
    ADD CONSTRAINT tag_locations_pkey PRIMARY KEY (id);


--
-- Name: tag_matchers_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY tag_matchers
    ADD CONSTRAINT tag_matchers_pkey PRIMARY KEY (id);


--
-- Name: taggings_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY taggings
    ADD CONSTRAINT taggings_pkey PRIMARY KEY (id);


--
-- Name: tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (id);


--
-- Name: temporal_report_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY temporal_report_jobs
    ADD CONSTRAINT temporal_report_jobs_pkey PRIMARY KEY (id);


--
-- Name: uploaded_files_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY uploaded_files
    ADD CONSTRAINT uploaded_files_pkey PRIMARY KEY (id);


--
-- Name: user_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY user_subscriptions
    ADD CONSTRAINT user_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: users_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY versions
    ADD CONSTRAINT versions_pkey PRIMARY KEY (id);


--
-- Name: collection_mission_task_eligibility; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX collection_mission_task_eligibility ON collection_mission_tasks USING btree (success, job_id, created_at, scheduled_at);


--
-- Name: collection_mission_tasks_on_collection_mission_id_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX collection_mission_tasks_on_collection_mission_id_idx ON collection_mission_tasks USING btree (collection_mission_id);


--
-- Name: collection_mission_tasks_on_created_at; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX collection_mission_tasks_on_created_at ON collection_mission_tasks USING btree (created_at);


--
-- Name: cube_match_dimensions_uniqueness; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX cube_match_dimensions_uniqueness ON cube_match_dimensions USING btree (source_id, source_type, domain, "column");


--
-- Name: cube_matches_uniqueness; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX cube_matches_uniqueness ON cube_matches USING btree (cube_id, cube_match_dimension_id, "row");


--
-- Name: custom_connections_on_custom_extraction_scheduling_recipe_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX custom_connections_on_custom_extraction_scheduling_recipe_id ON custom_connections USING btree (custom_extraction_scheduling_recipe_id);


--
-- Name: index_account_domains_on_account_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_account_domains_on_account_id ON account_domains USING btree (account_id);


--
-- Name: index_account_domains_on_account_id_and_name; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_account_domains_on_account_id_and_name ON account_domains USING btree (account_id, name);


--
-- Name: index_account_domains_on_admin_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_account_domains_on_admin_id ON account_domains USING btree (admin_id);


--
-- Name: index_account_state_transitions_on_account_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_account_state_transitions_on_account_id ON account_state_transitions USING btree (account_id);


--
-- Name: index_account_tokens_on_hashed_token; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_account_tokens_on_hashed_token ON account_tokens USING btree (hashed_token);


--
-- Name: index_accounts_admins_on_account_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_accounts_admins_on_account_id ON accounts_admins USING btree (account_id);


--
-- Name: index_accounts_admins_on_account_id_and_admin_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_accounts_admins_on_account_id_and_admin_id ON accounts_admins USING btree (account_id, admin_id);


--
-- Name: index_accounts_admins_on_admin_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_accounts_admins_on_admin_id ON accounts_admins USING btree (admin_id);


--
-- Name: index_accounts_on_name; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_accounts_on_name ON accounts USING btree (name);


--
-- Name: index_accounts_on_priority; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_accounts_on_priority ON accounts USING btree (priority);


--
-- Name: index_admins_on_email; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_admins_on_email ON admins USING btree (email);


--
-- Name: index_announcements_on_admin_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_announcements_on_admin_id ON announcements USING btree (admin_id);


--
-- Name: index_applets_on_dashboard_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_applets_on_dashboard_id ON applets USING btree (dashboard_id);


--
-- Name: index_applets_on_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_applets_on_user_id ON applets USING btree (user_id);


--
-- Name: index_applications_on_unique_type; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_applications_on_unique_type ON applications USING btree (lower((type)::text));


--
-- Name: index_authentication_tokens_on_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_authentication_tokens_on_user_id ON authentication_tokens USING btree (user_id);


--
-- Name: index_categories_on_name; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_categories_on_name ON categories USING btree (name);


--
-- Name: index_cmst_on_collection_mission_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_cmst_on_collection_mission_id ON collection_mission_state_transitions USING btree (collection_mission_id);


--
-- Name: index_collection_missions_on_connection_id_and_connection_type; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_collection_missions_on_connection_id_and_connection_type ON collection_missions USING btree (connection_id, connection_type);


--
-- Name: index_collection_missions_on_created_at; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_collection_missions_on_created_at ON collection_missions USING btree (created_at);


--
-- Name: index_collection_missions_on_target_id_and_target_type; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_collection_missions_on_target_id_and_target_type ON collection_missions USING btree (target_id, target_type);


--
-- Name: index_configurations_on_name; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_configurations_on_name ON configurations USING btree (name);


--
-- Name: index_connection_issues_on_connection_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_connection_issues_on_connection_id ON connection_issues USING btree (connection_id);


--
-- Name: index_connection_issues_on_connection_id_and_issue_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_connection_issues_on_connection_id_and_issue_id ON connection_issues USING btree (connection_id, issue_id);


--
-- Name: index_connection_semaphores_on_connection_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_connection_semaphores_on_connection_id ON connection_semaphores USING btree (connection_id);


--
-- Name: index_connections_on_authorization_unstable_at; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_connections_on_authorization_unstable_at ON connections USING btree (authorization_unstable_at);


--
-- Name: index_connections_on_custom_extraction_scheduling_recipe_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_connections_on_custom_extraction_scheduling_recipe_id ON connections USING btree (custom_extraction_scheduling_recipe_id);


--
-- Name: index_control_mission_state_transitions_on_control_mission_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_control_mission_state_transitions_on_control_mission_id ON control_mission_state_transitions USING btree (control_mission_id);


--
-- Name: index_control_mission_tasks_on_control_mission_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_control_mission_tasks_on_control_mission_id ON control_mission_tasks USING btree (control_mission_id);


--
-- Name: index_control_missions_on_installed_report_application_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_control_missions_on_installed_report_application_id ON control_missions USING btree (installed_report_application_id);


--
-- Name: index_custom_connections_on_account_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_custom_connections_on_account_id ON custom_connections USING btree (account_id);


--
-- Name: index_custom_connections_on_authorization_unstable_at; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_custom_connections_on_authorization_unstable_at ON custom_connections USING btree (authorization_unstable_at);


--
-- Name: index_custom_connections_on_data_source_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_custom_connections_on_data_source_id ON custom_connections USING btree (data_source_id);


--
-- Name: index_custom_connections_on_extraction_engine_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_custom_connections_on_extraction_engine_id ON custom_connections USING btree (extraction_engine_id);


--
-- Name: index_custom_connections_on_lookup_code; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_custom_connections_on_lookup_code ON custom_connections USING btree (lookup_code);


--
-- Name: index_custom_connections_on_schema_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_custom_connections_on_schema_id ON custom_connections USING btree (schema_id);


--
-- Name: index_custom_connections_on_sftp_account_name; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_custom_connections_on_sftp_account_name ON custom_connections USING btree (sftp_account_name);


--
-- Name: index_custom_connections_on_state; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_custom_connections_on_state ON custom_connections USING btree (state);


--
-- Name: index_custom_connections_on_subdirectory_name; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_custom_connections_on_subdirectory_name ON custom_connections USING btree (subdirectory_name);


--
-- Name: index_custom_fields_on_data_source_scope_id_and_name; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_custom_fields_on_data_source_scope_id_and_name ON custom_fields USING btree (data_source_scope_id, name);


--
-- Name: index_customer_favicons_on_created_at; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_customer_favicons_on_created_at ON customer_favicons USING btree (created_at);


--
-- Name: index_customer_logos_on_created_at; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_customer_logos_on_created_at ON customer_logos USING btree (created_at);


--
-- Name: index_dashboard_users_on_dashboard_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_dashboard_users_on_dashboard_id ON dashboard_users USING btree (dashboard_id);


--
-- Name: index_dashboard_users_on_dashboard_id_and_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_dashboard_users_on_dashboard_id_and_user_id ON dashboard_users USING btree (dashboard_id, user_id);


--
-- Name: index_dashboard_users_on_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_dashboard_users_on_user_id ON dashboard_users USING btree (user_id);


--
-- Name: index_dashboards_on_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_dashboards_on_user_id ON dashboards USING btree (user_id);


--
-- Name: index_email_templates_on_email_layout_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_email_templates_on_email_layout_id ON email_templates USING btree (email_layout_id);


--
-- Name: index_extraction_engines_on_type; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_extraction_engines_on_type ON extraction_engines USING btree (type);


--
-- Name: index_extractor_assets_on_extractor_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_extractor_assets_on_extractor_id ON extractor_assets USING btree (extractor_id);


--
-- Name: index_extractor_issues_on_extractor_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_extractor_issues_on_extractor_id ON extractor_issues USING btree (extractor_id);


--
-- Name: index_extractor_issues_on_extractor_id_and_issue_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_extractor_issues_on_extractor_id_and_issue_id ON extractor_issues USING btree (extractor_id, issue_id);


--
-- Name: index_extractor_rate_limits_on_extractor_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_extractor_rate_limits_on_extractor_id ON extractor_rate_limits USING btree (extractor_id);


--
-- Name: index_extractor_semaphores_on_extractor_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_extractor_semaphores_on_extractor_id ON extractor_semaphores USING btree (extractor_id);


--
-- Name: index_extractors_on_available; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_extractors_on_available ON extractors USING btree (available);


--
-- Name: index_extractors_on_extraction_scheduling_recipe_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_extractors_on_extraction_scheduling_recipe_id ON extractors USING btree (extraction_scheduling_recipe_id);


--
-- Name: index_extractors_on_schema_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_extractors_on_schema_id ON extractors USING btree (schema_id);


--
-- Name: index_extractors_on_unique_type; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_extractors_on_unique_type ON extractors USING btree (lower((type)::text));


--
-- Name: index_feature_flags_on_name_and_flaggable_type_and_flaggable_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_feature_flags_on_name_and_flaggable_type_and_flaggable_id ON feature_flags USING btree (name, flaggable_type, flaggable_id);


--
-- Name: index_fields_on_scope_id_and_name; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_fields_on_scope_id_and_name ON fields USING btree (scope_id, name);


--
-- Name: index_inbound_addresses_on_connection; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_inbound_addresses_on_connection ON inbound_email_addresses USING btree (connection_id, connection_type);


--
-- Name: index_inbound_email_addresses_on_to_address; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_inbound_email_addresses_on_to_address ON inbound_email_addresses USING btree (to_address);


--
-- Name: index_inbound_email_attachments_on_inbound_email_message_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_inbound_email_attachments_on_inbound_email_message_id ON inbound_email_attachments USING btree (inbound_email_message_id);


--
-- Name: index_inbound_email_messages_on_from_address; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_inbound_email_messages_on_from_address ON inbound_email_messages USING btree (from_address);


--
-- Name: index_inbound_email_messages_on_inbound_email_address_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_inbound_email_messages_on_inbound_email_address_id ON inbound_email_messages USING btree (inbound_email_address_id);


--
-- Name: index_installed_report_applications_on_report_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_installed_report_applications_on_report_id ON installed_report_applications USING btree (report_id);


--
-- Name: index_issues_on_vendor_and_vendor_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_issues_on_vendor_and_vendor_id ON issues USING btree (vendor, vendor_id);


--
-- Name: index_line_items_on_order_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_line_items_on_order_id ON line_items USING btree (order_id);


--
-- Name: index_line_items_on_product_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_line_items_on_product_id ON line_items USING btree (product_id);


--
-- Name: index_notification_deliveries_on_notification_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_notification_deliveries_on_notification_id ON notification_deliveries USING btree (notification_id);


--
-- Name: index_notification_delivery_state_transitions_on_delivery_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_notification_delivery_state_transitions_on_delivery_id ON notification_delivery_state_transitions USING btree (notification_delivery_id);


--
-- Name: index_orders_on_customer_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_orders_on_customer_id ON orders USING btree (customer_id);


--
-- Name: index_param_templates_on_extraction_engine_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_param_templates_on_extraction_engine_id ON param_templates USING btree (extraction_engine_id);


--
-- Name: index_password_resets_on_customer_id_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_password_resets_on_customer_id_id ON password_resets USING btree (customer_id_id);


--
-- Name: index_plan_categories_on_name; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_plan_categories_on_name ON plan_categories USING btree (name);


--
-- Name: index_platforms_on_account_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_platforms_on_account_id ON connections USING btree (account_id);


--
-- Name: index_platforms_on_extractor_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_platforms_on_extractor_id ON platforms USING btree (extractor_id);


--
-- Name: index_platforms_on_is_public; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_platforms_on_is_public ON platforms USING btree (is_public);


--
-- Name: index_platforms_on_provider_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_platforms_on_provider_id ON connections USING btree (platform_id);


--
-- Name: index_platforms_on_state; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_platforms_on_state ON connections USING btree (state);


--
-- Name: index_protected_operations_on_record_type_and_operation; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_protected_operations_on_record_type_and_operation ON protected_operations USING btree (record_type, operation);


--
-- Name: index_provider_categories_on_provider_id_and_category_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_provider_categories_on_provider_id_and_category_id ON platform_categories USING btree (platform_id, category_id);


--
-- Name: index_providers_on_title; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_providers_on_title ON platforms USING btree (title);


--
-- Name: index_rails_admin_histories; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_rails_admin_histories ON rails_admin_histories USING btree (item, "table", month, year);


--
-- Name: index_report_column_fields_on_data_source_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_report_column_fields_on_data_source_id ON report_column_fields USING btree (data_source_id);


--
-- Name: index_report_column_fields_on_field_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_report_column_fields_on_field_id ON report_column_fields USING btree (field_id);


--
-- Name: index_report_column_fields_on_report_column_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_report_column_fields_on_report_column_id ON report_column_fields USING btree (report_column_id);


--
-- Name: index_report_column_fields_on_report_custom_field_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_report_column_fields_on_report_custom_field_id ON report_column_fields USING btree (report_custom_field_id);


--
-- Name: index_report_columns_on_report_id_and_column_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_report_columns_on_report_id_and_column_id ON report_columns USING btree (report_id, column_id);


--
-- Name: index_report_data_sources_unique; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_report_data_sources_unique ON report_data_sources USING btree (report_id, data_source_id, old_scope_name);


--
-- Name: index_report_job_state_transitions_on_report_job_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_report_job_state_transitions_on_report_job_id ON report_job_state_transitions USING btree (report_job_id);


--
-- Name: index_report_jobs_on_report_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_report_jobs_on_report_id ON report_jobs USING btree (report_id);


--
-- Name: index_report_jobs_on_state; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_report_jobs_on_state ON report_jobs USING btree (state);


--
-- Name: index_report_jobs_on_updated_at; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_report_jobs_on_updated_at ON report_jobs USING btree (updated_at);


--
-- Name: index_report_template_columns_on_field_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_report_template_columns_on_field_id ON report_template_columns USING btree (field_id);


--
-- Name: index_report_users_on_report_id_and_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_report_users_on_report_id_and_user_id ON report_users USING btree (report_id, user_id);


--
-- Name: index_report_view_users_on_report_view_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_report_view_users_on_report_view_id ON report_view_users USING btree (report_view_id);


--
-- Name: index_report_view_users_on_report_view_id_and_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_report_view_users_on_report_view_id_and_user_id ON report_view_users USING btree (report_view_id, user_id);


--
-- Name: index_report_view_users_on_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_report_view_users_on_user_id ON report_view_users USING btree (user_id);


--
-- Name: index_report_views_on_report_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_report_views_on_report_id ON report_views USING btree (report_id);


--
-- Name: index_report_views_on_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_report_views_on_user_id ON report_views USING btree (user_id);


--
-- Name: index_reports_on_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_reports_on_user_id ON reports USING btree (user_id);


--
-- Name: index_roles_on_name; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_roles_on_name ON roles USING btree (name);


--
-- Name: index_schema_changes_on_target_id_and_target_type; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_schema_changes_on_target_id_and_target_type ON schema_changes USING btree (target_id, target_type);


--
-- Name: index_scopes_on_schema_id_and_name; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_scopes_on_schema_id_and_name ON scopes USING btree (schema_id, name);


--
-- Name: index_source_reports_on_data_source_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_source_reports_on_data_source_id ON source_reports USING btree (data_source_id);


--
-- Name: index_source_reports_on_schema_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_source_reports_on_schema_id ON source_reports USING btree (schema_id);


--
-- Name: index_staq_events_on_processed_at_and_created_at; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_staq_events_on_processed_at_and_created_at ON staq_events USING btree (processed_at, created_at);


--
-- Name: index_subscription_categories_on_name; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_subscription_categories_on_name ON subscription_categories USING btree (name);


--
-- Name: index_tag_locations_on_position; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_tag_locations_on_position ON tag_locations USING btree ("position");


--
-- Name: index_tag_locations_on_tag_location_category_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_tag_locations_on_tag_location_category_id ON tag_locations USING btree (tag_location_category_id);


--
-- Name: index_tag_matchers_on_position; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_tag_matchers_on_position ON tag_matchers USING btree ("position");


--
-- Name: index_taggings_on_taggable_id_and_taggable_type_and_context; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_taggings_on_taggable_id_and_taggable_type_and_context ON taggings USING btree (taggable_id, taggable_type, context);


--
-- Name: index_tags_on_name; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_tags_on_name ON tags USING btree (name);


--
-- Name: index_temporal_report_jobs_on_created_at; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_temporal_report_jobs_on_created_at ON temporal_report_jobs USING btree (created_at);


--
-- Name: index_temporal_report_jobs_on_data_source_id_and_scope_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_temporal_report_jobs_on_data_source_id_and_scope_id ON temporal_report_jobs USING btree (data_source_id, scope_id);


--
-- Name: index_temporal_report_jobs_on_state; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_temporal_report_jobs_on_state ON temporal_report_jobs USING btree (state);


--
-- Name: index_user_subscriptions_on_user_id_and_subscription_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_user_subscriptions_on_user_id_and_subscription_id ON user_subscriptions USING btree (user_id, subscription_id);


--
-- Name: index_users_on_account_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_users_on_account_id ON users USING btree (account_id);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_users_on_email ON users USING btree (email);


--
-- Name: index_users_on_invitation_token; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_users_on_invitation_token ON users USING btree (invitation_token);


--
-- Name: index_users_on_invitations_count; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_users_on_invitations_count ON users USING btree (invitations_count);


--
-- Name: index_users_on_invited_by_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_users_on_invited_by_id ON users USING btree (invited_by_id);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON users USING btree (reset_password_token);


--
-- Name: index_versions_on_item_type_and_item_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_versions_on_item_type_and_item_id ON versions USING btree (item_type, item_id);


--
-- Name: index_versions_on_transaction_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_versions_on_transaction_id ON versions USING btree (transaction_id);


--
-- Name: one_new_in_progress_mission_per_interval_per_connection_no_tgt; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX one_new_in_progress_mission_per_interval_per_connection_no_tgt ON collection_missions USING btree (connection_id, connection_type, mission_start_at, mission_end_at, verify_only) WHERE ((((state)::text = ANY ((ARRAY['new'::character varying, 'in_progress'::character varying])::text[])) AND (target_type IS NULL)) AND (created_at >= '2016-06-10 19:53:51'::timestamp without time zone));


--
-- Name: one_new_in_progress_mission_per_interval_per_connection_per_tgt; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX one_new_in_progress_mission_per_interval_per_connection_per_tgt ON collection_missions USING btree (connection_id, connection_type, mission_start_at, mission_end_at, verify_only, target_id, target_type) WHERE ((((state)::text = ANY ((ARRAY['new'::character varying, 'in_progress'::character varying])::text[])) AND (target_type IS NOT NULL)) AND (created_at >= '2016-06-10 19:53:51'::timestamp without time zone));


--
-- Name: schemas_id_key; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX schemas_id_key ON schemas USING btree (id);


--
-- Name: staq_events_obj_lookup; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX staq_events_obj_lookup ON staq_events USING btree (table_name, table_record_id, created_at);


--
-- Name: taggings_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX taggings_idx ON taggings USING btree (tag_id, taggable_id, taggable_type, context, tagger_id, tagger_type);


--
-- Name: unique_base_report_views; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX unique_base_report_views ON report_views USING btree (report_id) WHERE (parent_report_view_id IS NULL);


--
-- Name: unique_role_protect_operations_idx; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX unique_role_protect_operations_idx ON role_permitted_operations USING btree (role_id, protected_operation_id);


--
-- Name: unique_schema_migrations; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX unique_schema_migrations ON schema_migrations USING btree (version);


--
-- Name: _RETURN; Type: RULE; Schema: public; Owner: -
--

CREATE RULE "_RETURN" AS
    ON SELECT TO collection_mission_loading_batches DO INSTEAD  SELECT batches_of_missions."Load Group",
    batches_of_missions."Load Group Advisory Lock ID",
    to_char(batches_of_missions.earliest_created_at, 'MM/DD HH24:MI'::text) AS "Earliest Mission Created At",
    to_char(batches_of_missions.earliest_scheduled_at, 'MM/DD HH24:MI'::text) AS "Earliest Mission Scheduled At",
    batches_of_missions.count AS "# of Missions",
    batches_of_missions.array_agg AS "Mission IDs"
   FROM ( SELECT (((('Platform '::text || c.platform_id) || ' ('::text) || (p.title)::text) || ')'::text) AS "Load Group",
            hashtext(('Platform '::text || c.platform_id)) AS "Load Group Advisory Lock ID",
            min(cm.created_at) AS earliest_created_at,
            min(cm.scheduled_at) AS earliest_scheduled_at,
            count(cm.*) AS count,
            array_agg(cm.id) AS array_agg
           FROM ((collection_missions cm
             JOIN connections c ON ((c.id = cm.connection_id)))
             JOIN platforms p ON ((c.platform_id = p.id)))
          WHERE (((cm.connection_type)::text = 'Connection'::text) AND ((cm.state)::text = 'collected'::text))
          GROUP BY c.platform_id, p.title
        UNION ALL
         SELECT (((('Custom Connection '::text || cc.id) || ' ('::text) || (cc.name)::text) || ')'::text),
            hashtext(('Custom Connection '::text || cc.id)) AS hashtext,
            min(cm.created_at) AS min,
            min(cm.scheduled_at) AS min,
            count(cm.*) AS count,
            array_agg(cm.id) AS array_agg
           FROM (collection_missions cm
             JOIN custom_connections cc ON ((cc.id = cm.connection_id)))
          WHERE (((cm.connection_type)::text = 'CustomConnection'::text) AND ((cm.state)::text = 'collected'::text))
          GROUP BY cc.id) batches_of_missions
  ORDER BY batches_of_missions.earliest_scheduled_at, batches_of_missions.count DESC;


--
-- Name: admins_on_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER admins_on_insert_trigger AFTER INSERT ON admins FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: admins_on_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER admins_on_update_trigger AFTER UPDATE ON admins FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: announcements_on_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER announcements_on_update_trigger AFTER UPDATE ON announcements FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: applets_on_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER applets_on_insert_trigger AFTER INSERT ON applets FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: applets_on_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER applets_on_update_trigger AFTER UPDATE ON applets FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: collection_missions_on_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER collection_missions_on_insert_trigger AFTER INSERT ON collection_missions FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: collection_missions_on_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER collection_missions_on_update_trigger AFTER UPDATE ON collection_missions FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: connection_data_source_delete_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER connection_data_source_delete_trigger AFTER DELETE ON connections FOR EACH ROW EXECUTE PROCEDURE remove_data_source();


--
-- Name: connections_on_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER connections_on_insert_trigger AFTER INSERT ON connections FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: connections_on_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER connections_on_update_trigger AFTER UPDATE ON connections FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: create_inbound_email_address_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER create_inbound_email_address_trigger AFTER INSERT ON custom_connections FOR EACH ROW EXECUTE PROCEDURE create_inbound_email_address();


--
-- Name: custom_connection_data_source_delete_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER custom_connection_data_source_delete_trigger AFTER DELETE ON custom_connections FOR EACH ROW EXECUTE PROCEDURE remove_data_source();


--
-- Name: custom_connection_schema_delete_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER custom_connection_schema_delete_trigger AFTER DELETE ON custom_connections FOR EACH ROW EXECUTE PROCEDURE remove_schema();


--
-- Name: dashboard_users_on_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER dashboard_users_on_insert_trigger AFTER INSERT ON dashboard_users FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: enable_custom_connection_scopes_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER enable_custom_connection_scopes_trigger AFTER INSERT ON scopes FOR EACH ROW EXECUTE PROCEDURE default_custom_connection_scopes_to_enabled();


--
-- Name: extractor_schema_delete_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER extractor_schema_delete_trigger AFTER DELETE ON extractors FOR EACH ROW EXECUTE PROCEDURE remove_schema();


--
-- Name: inbound_email_messages_on_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER inbound_email_messages_on_insert_trigger AFTER INSERT ON inbound_email_messages FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: insert_base_report_view_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER insert_base_report_view_trigger AFTER INSERT ON reports FOR EACH ROW EXECUTE PROCEDURE insert_base_report_view();


--
-- Name: insert_creator_report_user_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER insert_creator_report_user_trigger AFTER INSERT ON reports FOR EACH ROW EXECUTE PROCEDURE insert_creator_report_user();


--
-- Name: insert_creator_report_view_user_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER insert_creator_report_view_user_trigger AFTER INSERT ON report_views FOR EACH ROW EXECUTE PROCEDURE insert_creator_report_view_user();


--
-- Name: insert_dashboard_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER insert_dashboard_trigger AFTER INSERT ON users FOR EACH ROW EXECUTE PROCEDURE insert_dashboard();


--
-- Name: insert_dashboard_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER insert_dashboard_trigger AFTER INSERT ON dashboards FOR EACH ROW EXECUTE PROCEDURE insert_dashboard_user();


--
-- Name: insert_visible_user_subscriptions_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER insert_visible_user_subscriptions_trigger AFTER INSERT ON users FOR EACH ROW EXECUTE PROCEDURE insert_visible_user_subscriptions();


--
-- Name: notification_deliveries_on_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notification_deliveries_on_insert_trigger AFTER INSERT ON notification_deliveries FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: notifications_on_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notifications_on_insert_trigger AFTER INSERT ON notifications FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: pi_confirm_announcements_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pi_confirm_announcements_trigger BEFORE INSERT OR UPDATE ON notifications FOR EACH ROW WHEN (((new.source_type)::text = 'Announcement'::text)) EXECUTE PROCEDURE pi_confirm_association_exists('source', 'announcements');


--
-- Name: pi_confirm_connections_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pi_confirm_connections_trigger BEFORE INSERT OR UPDATE ON inbound_email_addresses FOR EACH ROW WHEN (((new.connection_type)::text = 'Connection'::text)) EXECUTE PROCEDURE pi_confirm_association_exists('connection', 'connections');


--
-- Name: pi_confirm_connections_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pi_confirm_connections_trigger BEFORE INSERT OR UPDATE ON notifications FOR EACH ROW WHEN (((new.source_type)::text = 'Connection'::text)) EXECUTE PROCEDURE pi_confirm_association_exists('source', 'connections');


--
-- Name: pi_confirm_dashboard_users_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pi_confirm_dashboard_users_trigger BEFORE INSERT OR UPDATE ON notifications FOR EACH ROW WHEN (((new.source_type)::text = 'DashboardUser'::text)) EXECUTE PROCEDURE pi_confirm_association_exists('source', 'dashboard_users');


--
-- Name: pi_confirm_report_comments_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pi_confirm_report_comments_trigger BEFORE INSERT OR UPDATE ON notifications FOR EACH ROW WHEN (((new.source_type)::text = 'ReportComment'::text)) EXECUTE PROCEDURE pi_confirm_association_exists('source', 'report_comments');


--
-- Name: pi_confirm_report_view_users_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pi_confirm_report_view_users_trigger BEFORE INSERT OR UPDATE ON notifications FOR EACH ROW WHEN (((new.source_type)::text = 'ReportViewUser'::text)) EXECUTE PROCEDURE pi_confirm_association_exists('source', 'report_view_users');


--
-- Name: pi_delete_inbound_email_addresses_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pi_delete_inbound_email_addresses_trigger AFTER DELETE ON connections FOR EACH ROW EXECUTE PROCEDURE pi_delete_cascade('inbound_email_addresses', 'connection', 'Connection');


--
-- Name: pi_delete_notifications_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pi_delete_notifications_trigger AFTER DELETE ON report_comments FOR EACH ROW EXECUTE PROCEDURE pi_delete_cascade('notifications', 'source', 'ReportComment');


--
-- Name: pi_delete_notifications_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pi_delete_notifications_trigger AFTER DELETE ON report_view_users FOR EACH ROW EXECUTE PROCEDURE pi_delete_cascade('notifications', 'source', 'ReportViewUser');


--
-- Name: pi_delete_notifications_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pi_delete_notifications_trigger AFTER DELETE ON announcements FOR EACH ROW EXECUTE PROCEDURE pi_delete_cascade('notifications', 'source', 'Announcement');


--
-- Name: pi_delete_notifications_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pi_delete_notifications_trigger AFTER DELETE ON dashboard_users FOR EACH ROW EXECUTE PROCEDURE pi_delete_cascade('notifications', 'source', 'DashboardUser');


--
-- Name: pi_delete_notifications_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pi_delete_notifications_trigger AFTER DELETE ON connections FOR EACH ROW EXECUTE PROCEDURE pi_delete_cascade('notifications', 'source', 'Connection');


--
-- Name: platform_data_source_delete_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER platform_data_source_delete_trigger AFTER DELETE ON platforms FOR EACH ROW EXECUTE PROCEDURE remove_data_source();


--
-- Name: platforms_on_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER platforms_on_insert_trigger AFTER INSERT ON platforms FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: platforms_on_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER platforms_on_update_trigger AFTER UPDATE ON platforms FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: report_comments_on_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER report_comments_on_insert_trigger AFTER INSERT ON report_comments FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: report_comments_on_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER report_comments_on_update_trigger AFTER UPDATE ON report_comments FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: report_jobs_on_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER report_jobs_on_insert_trigger AFTER INSERT ON report_jobs FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: report_jobs_on_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER report_jobs_on_update_trigger AFTER UPDATE ON report_jobs FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: report_view_users_on_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER report_view_users_on_insert_trigger AFTER INSERT ON report_view_users FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: reports_on_insert_edited_at_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER reports_on_insert_edited_at_trigger BEFORE INSERT ON reports FOR EACH ROW EXECUTE PROCEDURE populate_reports_edited_at_by_on_insert();


--
-- Name: reports_on_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER reports_on_insert_trigger AFTER INSERT ON reports FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: reports_on_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER reports_on_update_trigger AFTER UPDATE ON reports FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: source_report_data_source_delete_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER source_report_data_source_delete_trigger AFTER DELETE ON source_reports FOR EACH ROW EXECUTE PROCEDURE remove_data_source();


--
-- Name: source_report_schema_delete_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER source_report_schema_delete_trigger AFTER DELETE ON source_reports FOR EACH ROW EXECUTE PROCEDURE remove_schema();


--
-- Name: staq_events_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER staq_events_insert_trigger AFTER INSERT ON staq_events FOR EACH ROW EXECUTE PROCEDURE send_new_staq_event_notice();


--
-- Name: users_on_insert_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER users_on_insert_trigger AFTER INSERT ON users FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: users_on_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER users_on_update_trigger AFTER UPDATE ON users FOR EACH ROW EXECUTE PROCEDURE create_staq_event_for_insert_or_update();


--
-- Name: account_domains_account_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY account_domains
    ADD CONSTRAINT account_domains_account_id_fk FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;


--
-- Name: account_domains_admin_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY account_domains
    ADD CONSTRAINT account_domains_admin_id_fk FOREIGN KEY (admin_id) REFERENCES admins(id);


--
-- Name: account_state_transitions_account_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY account_state_transitions
    ADD CONSTRAINT account_state_transitions_account_id_fk FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;


--
-- Name: account_tokens_account_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY account_tokens
    ADD CONSTRAINT account_tokens_account_id_fk FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;


--
-- Name: accounts_admins_account_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY accounts_admins
    ADD CONSTRAINT accounts_admins_account_id_fk FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;


--
-- Name: accounts_admins_admin_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY accounts_admins
    ADD CONSTRAINT accounts_admins_admin_id_fk FOREIGN KEY (admin_id) REFERENCES admins(id) ON DELETE CASCADE;


--
-- Name: announcements_admin_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY announcements
    ADD CONSTRAINT announcements_admin_id_fk FOREIGN KEY (admin_id) REFERENCES admins(id);


--
-- Name: applets_report_view_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY applets
    ADD CONSTRAINT applets_report_view_id_fk FOREIGN KEY (report_view_id) REFERENCES report_views(id) ON DELETE CASCADE;


--
-- Name: applets_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY applets
    ADD CONSTRAINT applets_user_id_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;


--
-- Name: collection_mission_state_transitions_collection_mission_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY collection_mission_state_transitions
    ADD CONSTRAINT collection_mission_state_transitions_collection_mission_id_fk FOREIGN KEY (collection_mission_id) REFERENCES collection_missions(id) ON DELETE CASCADE;


--
-- Name: connection_issues_connection_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY connection_issues
    ADD CONSTRAINT connection_issues_connection_id_fk FOREIGN KEY (connection_id) REFERENCES connections(id) ON DELETE CASCADE;


--
-- Name: connection_issues_issue_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY connection_issues
    ADD CONSTRAINT connection_issues_issue_id_fk FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE;


--
-- Name: connection_semaphores_connection_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY connection_semaphores
    ADD CONSTRAINT connection_semaphores_connection_id_fk FOREIGN KEY (connection_id) REFERENCES connections(id) ON DELETE CASCADE;


--
-- Name: connections_created_by_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY connections
    ADD CONSTRAINT connections_created_by_user_id_fk FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE SET NULL;


--
-- Name: connections_custom_extraction_scheduling_recipe_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY connections
    ADD CONSTRAINT connections_custom_extraction_scheduling_recipe_id_fk FOREIGN KEY (custom_extraction_scheduling_recipe_id) REFERENCES extraction_scheduling_recipes(id) ON DELETE SET NULL;


--
-- Name: connections_data_source_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY connections
    ADD CONSTRAINT connections_data_source_id_fk FOREIGN KEY (data_source_id) REFERENCES data_sources(id) ON DELETE CASCADE;


--
-- Name: connections_maintenance_by_admin_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY connections
    ADD CONSTRAINT connections_maintenance_by_admin_id_fk FOREIGN KEY (maintenance_by_admin_id) REFERENCES admins(id);


--
-- Name: control_mission_state_transitions_control_mission_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY control_mission_state_transitions
    ADD CONSTRAINT control_mission_state_transitions_control_mission_id_fk FOREIGN KEY (control_mission_id) REFERENCES control_missions(id) ON DELETE CASCADE;


--
-- Name: control_mission_tasks_control_mission_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY control_mission_tasks
    ADD CONSTRAINT control_mission_tasks_control_mission_id_fk FOREIGN KEY (control_mission_id) REFERENCES control_missions(id) ON DELETE CASCADE;


--
-- Name: control_missions_installed_report_application_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY control_missions
    ADD CONSTRAINT control_missions_installed_report_application_id_fk FOREIGN KEY (installed_report_application_id) REFERENCES installed_report_applications(id) ON DELETE CASCADE;


--
-- Name: cube_match_dimensions_scope_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY cube_match_dimensions
    ADD CONSTRAINT cube_match_dimensions_scope_id_fk FOREIGN KEY (scope_id) REFERENCES scopes(id) ON DELETE CASCADE;


--
-- Name: cube_match_values_cube_match_dimension_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY cube_match_values
    ADD CONSTRAINT cube_match_values_cube_match_dimension_id_fk FOREIGN KEY (cube_match_dimension_id) REFERENCES cube_match_dimensions(id) ON DELETE CASCADE;


--
-- Name: cube_match_values_cube_match_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY cube_match_values
    ADD CONSTRAINT cube_match_values_cube_match_id_fk FOREIGN KEY (cube_match_id) REFERENCES cube_matches(id) ON DELETE CASCADE;


--
-- Name: cube_matches_cube_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY cube_matches
    ADD CONSTRAINT cube_matches_cube_id_fk FOREIGN KEY (cube_id) REFERENCES cubes(id) ON DELETE CASCADE;


--
-- Name: cube_matches_cube_match_dimension_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY cube_matches
    ADD CONSTRAINT cube_matches_cube_match_dimension_id_fk FOREIGN KEY (cube_match_dimension_id) REFERENCES cube_match_dimensions(id) ON DELETE CASCADE;


--
-- Name: cube_rules_cube_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY cube_rules
    ADD CONSTRAINT cube_rules_cube_id_fk FOREIGN KEY (cube_id) REFERENCES cubes(id) ON DELETE CASCADE;


--
-- Name: cubes_account_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY cubes
    ADD CONSTRAINT cubes_account_id_fk FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;


--
-- Name: custom_connection_issues_custom_connection_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY custom_connection_issues
    ADD CONSTRAINT custom_connection_issues_custom_connection_id_fk FOREIGN KEY (custom_connection_id) REFERENCES custom_connections(id);


--
-- Name: custom_connection_issues_issue_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY custom_connection_issues
    ADD CONSTRAINT custom_connection_issues_issue_id_fk FOREIGN KEY (issue_id) REFERENCES issues(id);


--
-- Name: custom_connections_created_by_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY custom_connections
    ADD CONSTRAINT custom_connections_created_by_user_id_fk FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE SET NULL;


--
-- Name: custom_connections_custom_extraction_scheduling_recipe_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY custom_connections
    ADD CONSTRAINT custom_connections_custom_extraction_scheduling_recipe_id_fk FOREIGN KEY (custom_extraction_scheduling_recipe_id) REFERENCES extraction_scheduling_recipes(id);


--
-- Name: custom_connections_data_source_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY custom_connections
    ADD CONSTRAINT custom_connections_data_source_id_fk FOREIGN KEY (data_source_id) REFERENCES data_sources(id) ON DELETE CASCADE;


--
-- Name: custom_connections_extraction_engine_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY custom_connections
    ADD CONSTRAINT custom_connections_extraction_engine_id_fk FOREIGN KEY (extraction_engine_id) REFERENCES extraction_engines(id) ON DELETE CASCADE;


--
-- Name: custom_connections_maintenance_by_admin_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY custom_connections
    ADD CONSTRAINT custom_connections_maintenance_by_admin_id_fk FOREIGN KEY (maintenance_by_admin_id) REFERENCES admins(id);


--
-- Name: custom_connections_schema_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY custom_connections
    ADD CONSTRAINT custom_connections_schema_id_fk FOREIGN KEY (schema_id) REFERENCES schemas(id) ON DELETE CASCADE;


--
-- Name: custom_fields_data_source_scope_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY custom_fields
    ADD CONSTRAINT custom_fields_data_source_scope_id_fk FOREIGN KEY (data_source_scope_id) REFERENCES data_source_scopes(id) ON DELETE CASCADE;


--
-- Name: dashboard_users_dashboard_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_users
    ADD CONSTRAINT dashboard_users_dashboard_id_fk FOREIGN KEY (dashboard_id) REFERENCES dashboards(id) ON DELETE CASCADE;


--
-- Name: dashboard_users_sharer_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_users
    ADD CONSTRAINT dashboard_users_sharer_user_id_fk FOREIGN KEY (sharer_user_id) REFERENCES users(id) ON DELETE CASCADE;


--
-- Name: dashboard_users_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY dashboard_users
    ADD CONSTRAINT dashboard_users_user_id_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;


--
-- Name: data_source_fields_data_source_scope_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY data_source_fields
    ADD CONSTRAINT data_source_fields_data_source_scope_id_fk FOREIGN KEY (field_id) REFERENCES fields(id) ON DELETE CASCADE;


--
-- Name: data_source_fields_field_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY data_source_fields
    ADD CONSTRAINT data_source_fields_field_id_fk FOREIGN KEY (field_id) REFERENCES fields(id) ON DELETE CASCADE;


--
-- Name: data_source_scopes_data_source_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY data_source_scopes
    ADD CONSTRAINT data_source_scopes_data_source_id_fk FOREIGN KEY (data_source_id) REFERENCES data_sources(id) ON DELETE CASCADE;


--
-- Name: data_source_scopes_scope_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY data_source_scopes
    ADD CONSTRAINT data_source_scopes_scope_id_fk FOREIGN KEY (scope_id) REFERENCES scopes(id) ON DELETE CASCADE;


--
-- Name: email_templates_email_layout_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY email_templates
    ADD CONSTRAINT email_templates_email_layout_id_fk FOREIGN KEY (email_layout_id) REFERENCES email_layouts(id) ON DELETE CASCADE;


--
-- Name: extractor_assets_extractor_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY extractor_assets
    ADD CONSTRAINT extractor_assets_extractor_id_fk FOREIGN KEY (extractor_id) REFERENCES extractors(id) ON DELETE CASCADE;


--
-- Name: extractor_issues_extractor_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY extractor_issues
    ADD CONSTRAINT extractor_issues_extractor_id_fk FOREIGN KEY (extractor_id) REFERENCES extractors(id) ON DELETE CASCADE;


--
-- Name: extractor_issues_issue_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY extractor_issues
    ADD CONSTRAINT extractor_issues_issue_id_fk FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE;


--
-- Name: extractor_rate_limits_extractor_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY extractor_rate_limits
    ADD CONSTRAINT extractor_rate_limits_extractor_id_fk FOREIGN KEY (extractor_id) REFERENCES extractors(id) ON DELETE CASCADE;


--
-- Name: extractor_semaphores_extractor_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY extractor_semaphores
    ADD CONSTRAINT extractor_semaphores_extractor_id_fk FOREIGN KEY (extractor_id) REFERENCES extractors(id) ON DELETE CASCADE;


--
-- Name: extractor_time_zone_specifications_extractor_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY extractor_time_zone_specifications
    ADD CONSTRAINT extractor_time_zone_specifications_extractor_id_fk FOREIGN KEY (extractor_id) REFERENCES extractors(id) ON DELETE CASCADE;


--
-- Name: extractors_extraction_scheduling_recipe_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY extractors
    ADD CONSTRAINT extractors_extraction_scheduling_recipe_id_fk FOREIGN KEY (extraction_scheduling_recipe_id) REFERENCES extraction_scheduling_recipes(id) ON DELETE CASCADE;


--
-- Name: extractors_schema_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY extractors
    ADD CONSTRAINT extractors_schema_id_fk FOREIGN KEY (schema_id) REFERENCES schemas(id);


--
-- Name: fields_scope_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY fields
    ADD CONSTRAINT fields_scope_id_fk FOREIGN KEY (scope_id) REFERENCES scopes(id);


--
-- Name: inbound_email_attachments_inbound_email_message_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY inbound_email_attachments
    ADD CONSTRAINT inbound_email_attachments_inbound_email_message_id_fk FOREIGN KEY (inbound_email_message_id) REFERENCES inbound_email_messages(id) ON DELETE CASCADE;


--
-- Name: inbound_email_messages_inbound_email_address_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY inbound_email_messages
    ADD CONSTRAINT inbound_email_messages_inbound_email_address_id_fk FOREIGN KEY (inbound_email_address_id) REFERENCES inbound_email_addresses(id) ON DELETE CASCADE;


--
-- Name: inbound_files_custom_connection_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY inbound_files
    ADD CONSTRAINT inbound_files_custom_connection_id_fk FOREIGN KEY (custom_connection_id) REFERENCES custom_connections(id) ON DELETE CASCADE;


--
-- Name: inbound_google_files_custom_connection_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY inbound_google_files
    ADD CONSTRAINT inbound_google_files_custom_connection_id_fk FOREIGN KEY (custom_connection_id) REFERENCES custom_connections(id) ON DELETE CASCADE;


--
-- Name: installed_applications_application_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY installed_report_applications
    ADD CONSTRAINT installed_applications_application_id_fk FOREIGN KEY (application_id) REFERENCES applications(id) ON DELETE CASCADE;


--
-- Name: installed_report_applications_report_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY installed_report_applications
    ADD CONSTRAINT installed_report_applications_report_id_fk FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE;


--
-- Name: notification_deliveries_notification_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY notification_deliveries
    ADD CONSTRAINT notification_deliveries_notification_id_fk FOREIGN KEY (notification_id) REFERENCES notifications(id) ON DELETE CASCADE;


--
-- Name: notification_delivery_state_transitions_delivery_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY notification_delivery_state_transitions
    ADD CONSTRAINT notification_delivery_state_transitions_delivery_id_fk FOREIGN KEY (notification_delivery_id) REFERENCES notification_deliveries(id) ON DELETE CASCADE;


--
-- Name: notifications_subscription_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY notifications
    ADD CONSTRAINT notifications_subscription_id_fk FOREIGN KEY (subscription_id) REFERENCES subscriptions(id) ON DELETE CASCADE;


--
-- Name: notifications_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY notifications
    ADD CONSTRAINT notifications_user_id_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;


--
-- Name: platforms_account_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY connections
    ADD CONSTRAINT platforms_account_id_fk FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;


--
-- Name: platforms_data_source_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY platforms
    ADD CONSTRAINT platforms_data_source_id_fk FOREIGN KEY (data_source_id) REFERENCES data_sources(id) ON DELETE CASCADE;


--
-- Name: platforms_extractor_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY platforms
    ADD CONSTRAINT platforms_extractor_id_fk FOREIGN KEY (extractor_id) REFERENCES extractors(id) ON DELETE CASCADE;


--
-- Name: platforms_provider_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY connections
    ADD CONSTRAINT platforms_provider_id_fk FOREIGN KEY (platform_id) REFERENCES platforms(id) ON DELETE CASCADE;


--
-- Name: provider_categories_category_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY platform_categories
    ADD CONSTRAINT provider_categories_category_id_fk FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE;


--
-- Name: provider_categories_provider_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY platform_categories
    ADD CONSTRAINT provider_categories_provider_id_fk FOREIGN KEY (platform_id) REFERENCES platforms(id) ON DELETE CASCADE;


--
-- Name: report_column_fields_data_source_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_column_fields
    ADD CONSTRAINT report_column_fields_data_source_id_fk FOREIGN KEY (data_source_id) REFERENCES data_sources(id) ON DELETE CASCADE;


--
-- Name: report_column_fields_field_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_column_fields
    ADD CONSTRAINT report_column_fields_field_id_fk FOREIGN KEY (field_id) REFERENCES fields(id);


--
-- Name: report_column_fields_report_column_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_column_fields
    ADD CONSTRAINT report_column_fields_report_column_id_fk FOREIGN KEY (report_column_id) REFERENCES report_columns(id) ON DELETE CASCADE;


--
-- Name: report_column_fields_report_custom_field_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_column_fields
    ADD CONSTRAINT report_column_fields_report_custom_field_id_fk FOREIGN KEY (report_custom_field_id) REFERENCES report_custom_fields(id) ON DELETE CASCADE;


--
-- Name: report_column_filters_report_column_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_column_filters
    ADD CONSTRAINT report_column_filters_report_column_id_fk FOREIGN KEY (report_column_id) REFERENCES report_columns(id) ON DELETE CASCADE;


--
-- Name: report_column_filters_report_filter_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_column_filters
    ADD CONSTRAINT report_column_filters_report_filter_id_fk FOREIGN KEY (report_filter_id) REFERENCES report_filters(id) ON DELETE CASCADE;


--
-- Name: report_columns_field_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_columns
    ADD CONSTRAINT report_columns_field_id_fk FOREIGN KEY (field_id) REFERENCES fields(id);


--
-- Name: report_columns_report_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_columns
    ADD CONSTRAINT report_columns_report_id_fk FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE;


--
-- Name: report_comments_report_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_comments
    ADD CONSTRAINT report_comments_report_id_fk FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE;


--
-- Name: report_comments_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_comments
    ADD CONSTRAINT report_comments_user_id_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;


--
-- Name: report_custom_fields_custom_field_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_custom_fields
    ADD CONSTRAINT report_custom_fields_custom_field_id_fk FOREIGN KEY (custom_field_id) REFERENCES custom_fields(id) ON DELETE CASCADE;


--
-- Name: report_custom_fields_report_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_custom_fields
    ADD CONSTRAINT report_custom_fields_report_id_fk FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE;


--
-- Name: report_data_source_filters_field_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_data_source_filters
    ADD CONSTRAINT report_data_source_filters_field_id_fk FOREIGN KEY (field_id) REFERENCES fields(id);


--
-- Name: report_data_source_filters_report_data_source_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_data_source_filters
    ADD CONSTRAINT report_data_source_filters_report_data_source_id_fk FOREIGN KEY (report_data_source_id) REFERENCES report_data_sources(id) ON DELETE CASCADE;


--
-- Name: report_data_source_filters_report_filter_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_data_source_filters
    ADD CONSTRAINT report_data_source_filters_report_filter_id_fk FOREIGN KEY (report_filter_id) REFERENCES report_filters(id) ON DELETE CASCADE;


--
-- Name: report_data_sources_data_source_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_data_sources
    ADD CONSTRAINT report_data_sources_data_source_id_fk FOREIGN KEY (data_source_id) REFERENCES data_sources(id) ON DELETE CASCADE;


--
-- Name: report_data_sources_report_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_data_sources
    ADD CONSTRAINT report_data_sources_report_id_fk FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE;


--
-- Name: report_data_sources_scope_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_data_sources
    ADD CONSTRAINT report_data_sources_scope_id_fk FOREIGN KEY (scope_id) REFERENCES scopes(id);


--
-- Name: report_job_state_transitions_report_job_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_job_state_transitions
    ADD CONSTRAINT report_job_state_transitions_report_job_id_fk FOREIGN KEY (report_job_id) REFERENCES report_jobs(id) ON DELETE CASCADE;


--
-- Name: report_jobs_report_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_jobs
    ADD CONSTRAINT report_jobs_report_id_fk FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE;


--
-- Name: report_template_columns_field_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_template_columns
    ADD CONSTRAINT report_template_columns_field_id_fk FOREIGN KEY (field_id) REFERENCES fields(id) ON DELETE CASCADE;


--
-- Name: report_template_columns_report_template_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_template_columns
    ADD CONSTRAINT report_template_columns_report_template_id_fk FOREIGN KEY (report_template_id) REFERENCES report_templates(id) ON DELETE CASCADE;


--
-- Name: report_users_report_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_users
    ADD CONSTRAINT report_users_report_id_fk FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE;


--
-- Name: report_users_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_users
    ADD CONSTRAINT report_users_user_id_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;


--
-- Name: report_view_database_accounts_account_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_view_database_accounts
    ADD CONSTRAINT report_view_database_accounts_account_id_fk FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;


--
-- Name: report_view_database_accounts_report_view_database_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_view_database_accounts
    ADD CONSTRAINT report_view_database_accounts_report_view_database_id_fk FOREIGN KEY (report_view_database_id) REFERENCES report_view_databases(id) ON DELETE CASCADE;


--
-- Name: report_view_users_report_view_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_view_users
    ADD CONSTRAINT report_view_users_report_view_id_fk FOREIGN KEY (report_view_id) REFERENCES report_views(id) ON DELETE CASCADE;


--
-- Name: report_view_users_sharer_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_view_users
    ADD CONSTRAINT report_view_users_sharer_user_id_fk FOREIGN KEY (sharer_user_id) REFERENCES users(id) ON DELETE CASCADE;


--
-- Name: report_view_users_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_view_users
    ADD CONSTRAINT report_view_users_user_id_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;


--
-- Name: report_views_parent_report_view_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_views
    ADD CONSTRAINT report_views_parent_report_view_id_fk FOREIGN KEY (parent_report_view_id) REFERENCES report_views(id) ON DELETE CASCADE;


--
-- Name: report_views_report_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_views
    ADD CONSTRAINT report_views_report_id_fk FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE;


--
-- Name: report_views_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY report_views
    ADD CONSTRAINT report_views_user_id_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;


--
-- Name: reports_edited_by_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports
    ADD CONSTRAINT reports_edited_by_user_id_fk FOREIGN KEY (edited_by_user_id) REFERENCES users(id);


--
-- Name: reports_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY reports
    ADD CONSTRAINT reports_user_id_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;


--
-- Name: role_permitted_operations_protected_operation_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY role_permitted_operations
    ADD CONSTRAINT role_permitted_operations_protected_operation_id_fk FOREIGN KEY (protected_operation_id) REFERENCES protected_operations(id) ON DELETE CASCADE;


--
-- Name: role_permitted_operations_role_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY role_permitted_operations
    ADD CONSTRAINT role_permitted_operations_role_id_fk FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE;


--
-- Name: scopes_schema_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY scopes
    ADD CONSTRAINT scopes_schema_id_fk FOREIGN KEY (schema_id) REFERENCES schemas(id);


--
-- Name: source_reports_account_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY source_reports
    ADD CONSTRAINT source_reports_account_id_fk FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;


--
-- Name: source_reports_data_source_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY source_reports
    ADD CONSTRAINT source_reports_data_source_id_fk FOREIGN KEY (data_source_id) REFERENCES data_sources(id) ON DELETE CASCADE;


--
-- Name: source_reports_data_source_scope_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY source_reports
    ADD CONSTRAINT source_reports_data_source_scope_id_fk FOREIGN KEY (data_source_scope_id) REFERENCES data_source_scopes(id) ON DELETE CASCADE;


--
-- Name: source_reports_report_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY source_reports
    ADD CONSTRAINT source_reports_report_id_fk FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE;


--
-- Name: source_reports_schema_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY source_reports
    ADD CONSTRAINT source_reports_schema_id_fk FOREIGN KEY (schema_id) REFERENCES schemas(id);


--
-- Name: subscriptions_email_template_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY subscriptions
    ADD CONSTRAINT subscriptions_email_template_id_fk FOREIGN KEY (email_template_id) REFERENCES email_templates(id);


--
-- Name: subscriptions_subscription_category_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY subscriptions
    ADD CONSTRAINT subscriptions_subscription_category_id_fk FOREIGN KEY (subscription_category_id) REFERENCES subscription_categories(id) ON DELETE CASCADE;


--
-- Name: support_requests_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY support_requests
    ADD CONSTRAINT support_requests_user_id_fk FOREIGN KEY (user_id) REFERENCES users(id);


--
-- Name: tag_locations_tag_location_category_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY tag_locations
    ADD CONSTRAINT tag_locations_tag_location_category_id_fk FOREIGN KEY (tag_location_category_id) REFERENCES tag_location_categories(id) ON DELETE CASCADE;


--
-- Name: temporal_report_jobs_created_from_report_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY temporal_report_jobs
    ADD CONSTRAINT temporal_report_jobs_created_from_report_id_fk FOREIGN KEY (created_from_report_id) REFERENCES reports(id) ON DELETE CASCADE;


--
-- Name: temporal_report_jobs_data_source_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY temporal_report_jobs
    ADD CONSTRAINT temporal_report_jobs_data_source_id_fk FOREIGN KEY (data_source_id) REFERENCES data_sources(id) ON DELETE CASCADE;


--
-- Name: temporal_report_jobs_scope_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY temporal_report_jobs
    ADD CONSTRAINT temporal_report_jobs_scope_id_fk FOREIGN KEY (scope_id) REFERENCES scopes(id) ON DELETE CASCADE;


--
-- Name: temporal_report_jobs_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY temporal_report_jobs
    ADD CONSTRAINT temporal_report_jobs_user_id_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;


--
-- Name: user_subscriptions_subscription_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY user_subscriptions
    ADD CONSTRAINT user_subscriptions_subscription_id_fk FOREIGN KEY (subscription_id) REFERENCES subscriptions(id) ON DELETE CASCADE;


--
-- Name: user_subscriptions_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY user_subscriptions
    ADD CONSTRAINT user_subscriptions_user_id_fk FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;


--
-- Name: users_account_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_account_id_fk FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;


--
-- Name: users_invited_by_user_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_invited_by_user_id_fk FOREIGN KEY (invited_by_user_id) REFERENCES users(id);


--
-- Name: users_role_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_role_id_fk FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

SET search_path = public, pg_catalog;

--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY schema_migrations (version) FROM stdin;
20120428174212
20120429193135
20120501220222
20120502204324
20120504200725
20120506153449
20120514153729
20120514154009
20120514154302
20120514154538
20120514155815
20120522203951
20120523165622
20120607003940
20120607004222
20120607164847
20120619153141
20120621181549
20120622201928
20120623151237
20120623182621
20120623183012
20120626161948
20120626162822
20120626182248
20120627172948
20120707145251
20120710153907
20120712003539
20120713182809
20120713183405
20120717134534
20120718124227
20120719154959
20120719160616
20120719162958
20120724154330
20120724155503
20120823002354
20120827141948
20120827172748
20120829190213
20120829191823
20120830174500
20120901185757
20120904140611
20120910135123
20120910135401
20120910170156
20120910174159
20120918183543
20120919151814
20120920145840
20120927014437
20120928175722
20121017163343
20121017164924
20121017165117
20121017170617
20121017170803
20121017172138
20121017173007
20121017175920
20121017180449
20121017181052
20121017193233
20121017203458
20121018132343
20121024152051
20121024152756
20121024152859
20121024153642
20121024171936
20121024172156
20121024172509
20121024172616
20121024174944
20121024175213
20121025192525
20121025215654
20121026163919
20121026164052
20121026171235
20121026172124
20121026172638
20121026181412
20121026190406
20121026193250
20121026194524
20121028003856
20121029174707
20121030153518
20121030170838
20121031175019
20121110160259
20121112164258
20121112224953
20121114203622
20121121141716
20121121143930
20121122152924
20121124192515
20121126175339
20121126180634
20121126203108
20121127152219
20121205155719
20121206155049
20121217152239
20121223205822
20121227184424
20121231190958
20121228201823
20121228221207
20121229155623
20121231201220
20130102151618
20130102155235
20130103152046
20130103162555
20130103205627
20130104210700
20121201213347
20130111154334
20130111205848
20130123193933
20130327164625
20130514000534
20130529155926
20130606182127
20130606195847
20130614145404
20130614150714
20130620192805
20130621153018
20130623200604
20130625191024
20130628184538
20130705192509
20130712232001
20130712232047
20130713154252
20130713155346
20130713160312
20130713160426
20130720015042
20130720020155
20130724190723
20130729181401
20130802192424
20130802193752
20130805153420
20130806194908
20130806225308
20130807123548
20130807145145
20130807230628
20130808171509
20130812115656
20130813143058
20130813192238
20130815181108
20130815181403
20130815183134
20130815183653
20130815183907
20130816002630
20130816180912
20130820215145
20130823151959
20130828174454
20130828181855
20130829144533
20130830124517
20130904162026
20130906191856
20130910154849
20130910191247
20130922195117
20130924154537
20130926154537
20131015151346
20131015152408
20131015164116
20131015164348
20131015181943
20131021191843
20131017215642
20131017232617
20131017232658
20131017232723
20131017232742
20131018005632
20131024233216
20131024155804
20131025042116
20131030165740
20131105183331
20131105184038
20131105184345
20131105184849
20131108161141
20131108161856
20131108161507
20131109160531
20131109160629
20131114162809
20131115151329
20131115193559
20131115201343
20131119165306
20131122184630
20131124204345
20131124204444
20131203204908
20131209184415
20131210153958
20131211184603
20131211184611
20131218172435
20131218174258
20131213181541
20131218161425
20140102233424
20140102233435
20140102233436
20140102233437
20140110040723
20140108174131
20140110203349
20140114001748
20140115054527
20140115161411
20140117063409
20140123154858
20140128174207
20140130152603
20140130152624
20140131172638
20140131173520
20140131174330
20140131192501
20140131200011
20140203165800
20140203235631
20140204172505
20140205153534
20140206154017
20140210143438
20140210173048
20140211170612
20140217191601
20140218145603
20140219194640
20140221145034
20140227181321
20140227190550
20140227190626
20140227190710
20140227190313
20140303171245
20140227190639
20140228172623
20140228191312
20140228204956
20140302213530
20140302155651
20140305173402
20140312211337
20140303172711
20140309183450
20140312130857
20140311204635
20140314133554
20140317153514
20140319173735
20140320172608
20140320172751
20140320202712
20140326182149
20140327171211
20140407171247
20140317182614
20140416205927
20140424202344
20140428135047
20140501145704
20140502024412
20140502024455
20140502193026
20140502144350
20140506173104
20140506181240
20140506211738
20140507162633
20140508024154
20140509205756
20140508143852
20140508143853
20140508143854
20140508143855
20140512173435
20140513195320
20140515181532
20140515181716
20140515181903
20140519155254
20140519174632
20140520143814
20140520150056
20140520170234
20140520171037
20140520174049
20140520214806
20140523010832
20140523165040
20140527155027
20140527155148
20140529002848
20140529131716
20140529132233
20140514195117
20140602194253
20140602235018
20140603191630
20140530181428
20140602173038
20140617181434
20140610152119
20140609200743
20140606160803
20140619174827
20140623135357
20140623155240
20140624185526
20140623150234
20140624025052
20140624081907
20140625032803
20140625154731
20140625183527
20140626151654
20140626205151
20140629210506
20140630170423
20140701184153
20140701184214
20140703183607
20140703184609
20140703184847
20140703185312
20140703185814
20140704142313
20140707113838
20140707152719
20140711164238
20140711164257
20140711164333
20140714165018
20140714170511
20140714175955
20140716153933
20140716160312
20140717130627
20140718021713
20140721152344
20140721153247
20140721153943
20140723165635
20140731142455
20140808145710
20140811190522
20140811203449
20140811204608
20140812194802
20140812202507
20140813192348
20140819171724
20140820164856
20140820175825
20140820182435
20140820182542
20140821194840
20140821195113
20140821203744
20140821204300
20140827151057
20140827183759
20140829165554
20140902161316
20140903223906
20140903232531
20140902161533
20140909190950
20140911222531
20140914201429
20140910162209
20140910162250
20140910162320
20140910162347
20140910175420
20140916200054
20140917153100
20140904172501
20140911023753
20141003131154
20141002183955
20141008215950
20141009202313
20141010203608
20141013165803
20141013182623
20141008023239
20141016133028
20141016200654
20141021050411
20141021050910
20141021052017
20141021053702
20141021204115
20141020160941
20141022035354
20141022040757
20141022142705
20141021205020
20141021205242
20141024195533
20141024195732
20141105142508
20141105213601
20141116192016
20141116205311
20141114161353
20141117152923
20141124212231
20141124212240
20141126174929
20141120165223
20141120165224
20141120165225
20141201180124
20141201194945
20141031192554
20141031200147
20141031200322
20141031200930
20141031201142
20141031203926
20141031204213
20141031204505
20141112204414
20141115195601
20141117190607
20141203164558
20141202175011
20141202194306
20141203194907
20141203195110
20141204045018
20141204202653
20141201213650
20141205154804
20141209201600
20141209201620
20141209201640
20141209201650
20141215200429
20141215203514
20141208161000
20141209212211
20141209212212
20141217203758
20141217211908
20141217184627
20141218134540
20141218213526
20141218215403
20141219184329
20141222153924
20141222203611
20141222205145
20141229141235
20141231153024
20150102153754
20150102200412
20150114132244
20150114174751
20150123175231
20150114180031
20150202161625
20150206031752
20150203042722
20150209024711
20141218153748
20150210195656
20150213010747
20150213010951
20150212003757
20150216180752
20150219195540
20150220152100
20150220162241
20150220175930
20150220173301
20150220195921
20150220195942
20150223174832
20150223175447
20150223175736
20150223191441
20150223175326
20150226003651
20150227201502
20150301034008
20150301034030
20150301034043
20150304213437
20150308154956
20150308031659
20150310203235
20150318145648
20150320151750
20150323193108
20150320223948
20150330165951
20150401140105
20150331162542
20150331163542
20150406163845
20150406164322
20150409151321
20150409151602
20150411193112
20150411193505
20150412001747
20150412154704
20150331175520
20150331175521
20150331175530
20150401032133
20150401032134
20150401181142
20150403141059
20150403141100
20150403141101
20150403141102
20150407000916
20150407001236
20150407001830
20150407001932
20150413003651
20150413185744
20150413193657
20150414150230
20150414173033
20150415154340
20150416213944
20150417151910
20150417152545
20150421151034
20150421160300
20150423190540
20150424143246
20150424161442
20150427131335
20150429154640
20150430150753
20150501165323
20150503192843
20150505145310
20150505195007
20150505153310
20150511130256
20150512181330
20150514205506
20150427214206
20150427214207
20150505182849
20150515043158
20150429115041
20150427214208
20150504140330
20150504140331
20150420190312
20150420215821
20150526175247
20150518181748
20150526175323
20150602201213
20150526191610
20150601133407
20150604152241
20150605161209
20150604212741
20150611203418
20150622134823
20150624215629
20150706161023
20150706164314
20150629145948
20150710165234
20150713121209
20150714170535
20150721153247
20150721175511
20150723192823
20150727204702
20150803144213
20150803144330
20150804171637
20150724162543
20150805203352
20150709205833
20150709205925
20150710174619
20150716190837
20150716191544
20150716194240
20150803164527
20150812164353
20150813213737
20150813190653
20150828153530
20150902203725
20150824181542
20150902193026
20150903140556
20150903140715
20150903151613
20150910171249
20150911160643
20150911183542
20150911183739
20150910212251
20150915140743
20150914191047
20150911204629
20150918163134
20150925152525
20151001153733
20151002231321
20151006033447
20151006033641
20151006044956
20151009135844
20151009174751
20151009175046
20151012190526
20151015142134
20151018213644
20151018213709
20151021224429
20151022171751
20151027170914
20151009182030
20151029185934
20151029185948
20151029211619
20151029212803
20151028190122
20151112155955
20151116145022
20151203183401
20151221173131
20151212042804
20151231180517
20160104201543
20160110043314
20160115154805
20160127172148
20160201031039
20160204170234
20160205022416
20160209154905
20160219160503
20160229215418
20160302153217
20160302153218
20160302153220
20160304004609
20160305012810
20160309000043
20160312020854
20160315192531
20160329144400
20160325162945
20160325164019
20160401181017
20160406193427
20160406210955
20160406211338
20160406213122
20160407163745
20160407194306
20160419192653
20160316182854
20160420211550
20160301215517
20160425143009
20160425204518
20160210215039
20160210220349
20160214203758
20160215053847
20160427201007
20160428171917
20160503190249
20160511184557
20160512194122
20160527043509
20160527145616
20160531151836
20160531175605
20160601201234
20160607191541
20160608193023
20160611150421
20160611150438
20160527172412
20160613213522
20160613213635
20160616184620
20160620165254
20160615172151
20160607145301
20160630192254
20160701194400
20160620171822
20160718202029
20160713142053
20160715164604
20160504204335
20160504210025
20160715164606
20160715164610
20160727194229
20160728160014
20160728031322
20160803180030
20160804234211
20160817195700
20160819175918
20160913182622
20160907151410
20160909160114
20160829161938
20160920160019
20160920174952
20160921173514
\.


--
-- PostgreSQL database dump complete
--

