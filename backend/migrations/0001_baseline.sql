-- Baseline: full schema as of 2026-07-09 (commit 4d495da, pre-FK migration),
-- generated with pg_dump --schema-only --no-owner --no-privileges from a dev DB
-- synced by TypeORM from the entities (entities were then the source of truth).
--
-- EXECUTED only on an EMPTY database (fresh dev/staging). On any database that
-- already has the schema (live prod, existing dev DBs) the runner STAMPS this
-- file as applied without executing it — see migration-runner.ts.

--
-- PostgreSQL database dump
--

\restrict QdBeEoJl9FD5x5ZPxpr9zMBVsOiYxpN3uo2dO7SWucLM0o4AEHhD7aF2k8GZmny

-- Dumped from database version 16.13
-- Dumped by pg_dump version 16.13

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: friend_requests_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.friend_requests_status_enum AS ENUM (
    'pending',
    'accepted',
    'rejected'
);


--
-- Name: messages_deliverystatus_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.messages_deliverystatus_enum AS ENUM (
    'SENDING',
    'SENT',
    'DELIVERED',
    'READ'
);


--
-- Name: messages_messagetype_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.messages_messagetype_enum AS ENUM (
    'TEXT',
    'PING',
    'IMAGE',
    'VOICE',
    'GIF',
    'FILE'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: blocked_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blocked_users (
    id integer NOT NULL,
    blocker_id integer,
    blocked_id integer
);


--
-- Name: blocked_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.blocked_users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: blocked_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.blocked_users_id_seq OWNED BY public.blocked_users.id;


--
-- Name: conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversations (
    id integer NOT NULL,
    "createdAt" timestamp without time zone DEFAULT now() NOT NULL,
    "disappearingTimer" integer,
    user_one_id integer,
    user_two_id integer,
    "pinnedMessageId" integer,
    "pinnedAt" timestamp without time zone,
    "pinnedByUserId" integer
);


--
-- Name: conversations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.conversations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: conversations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.conversations_id_seq OWNED BY public.conversations.id;


--
-- Name: fcm_token; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fcm_token (
    id integer NOT NULL,
    "userId" integer NOT NULL,
    token character varying NOT NULL,
    platform character varying DEFAULT 'web'::character varying NOT NULL,
    "createdAt" timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: fcm_token_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.fcm_token_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fcm_token_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.fcm_token_id_seq OWNED BY public.fcm_token.id;


--
-- Name: friend_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.friend_requests (
    id integer NOT NULL,
    status public.friend_requests_status_enum DEFAULT 'pending'::public.friend_requests_status_enum NOT NULL,
    "createdAt" timestamp without time zone DEFAULT now() NOT NULL,
    "respondedAt" timestamp without time zone,
    sender_id integer,
    receiver_id integer
);


--
-- Name: friend_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.friend_requests_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: friend_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.friend_requests_id_seq OWNED BY public.friend_requests.id;


--
-- Name: key_bundles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.key_bundles (
    id integer NOT NULL,
    "userId" integer NOT NULL,
    "registrationId" integer NOT NULL,
    "identityPublicKey" text NOT NULL,
    "signedPreKeyId" integer NOT NULL,
    "signedPreKeyPublic" text NOT NULL,
    "signedPreKeySignature" text NOT NULL,
    "createdAt" timestamp without time zone DEFAULT now() NOT NULL,
    "updatedAt" timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: key_bundles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.key_bundles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: key_bundles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.key_bundles_id_seq OWNED BY public.key_bundles.id;


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    id integer NOT NULL,
    content text NOT NULL,
    "encryptedContent" text,
    "deliveryStatus" public.messages_deliverystatus_enum DEFAULT 'SENT'::public.messages_deliverystatus_enum NOT NULL,
    "expiresAt" timestamp without time zone,
    "messageType" public.messages_messagetype_enum DEFAULT 'TEXT'::public.messages_messagetype_enum NOT NULL,
    "mediaUrl" text,
    "mediaDuration" integer,
    "hiddenByUserIds" text DEFAULT ''::text NOT NULL,
    reactions text,
    "linkPreviewUrl" text,
    "linkPreviewTitle" text,
    "linkPreviewImageUrl" text,
    "replyToMessageId" integer,
    "createdAt" timestamp without time zone DEFAULT now() NOT NULL,
    reply_to_message_id integer,
    sender_id integer,
    conversation_id integer,
    "disappearAfterSeconds" integer,
    "editedAt" timestamp without time zone
);


--
-- Name: messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.messages_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.messages_id_seq OWNED BY public.messages.id;


--
-- Name: one_time_pre_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.one_time_pre_keys (
    id integer NOT NULL,
    "userId" integer NOT NULL,
    "keyId" integer NOT NULL,
    "publicKey" text NOT NULL,
    used boolean DEFAULT false NOT NULL,
    "createdAt" timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: one_time_pre_keys_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.one_time_pre_keys_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: one_time_pre_keys_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.one_time_pre_keys_id_seq OWNED BY public.one_time_pre_keys.id;


--
-- Name: refresh_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refresh_tokens (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id integer NOT NULL,
    token_hash character varying(64) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: secret_notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.secret_notes (
    id integer NOT NULL,
    token character varying(64) NOT NULL,
    ciphertext text NOT NULL,
    "expiresAt" timestamp without time zone NOT NULL,
    "creatorId" integer,
    "createdAt" timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: secret_notes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.secret_notes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: secret_notes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.secret_notes_id_seq OWNED BY public.secret_notes.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id integer NOT NULL,
    username character varying NOT NULL,
    tag character varying(4) DEFAULT '0000'::character varying NOT NULL,
    password character varying NOT NULL,
    "profilePictureUrl" character varying,
    "profilePicturePublicId" character varying,
    "createdAt" timestamp without time zone DEFAULT now() NOT NULL,
    "passwordChangedAt" timestamp without time zone
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: web_push_subscription; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.web_push_subscription (
    id integer NOT NULL,
    "userId" integer NOT NULL,
    endpoint text NOT NULL,
    p256dh text NOT NULL,
    auth text NOT NULL,
    "userAgent" character varying,
    "expirationTime" bigint,
    "createdAt" timestamp without time zone DEFAULT now() NOT NULL,
    "updatedAt" timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: web_push_subscription_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.web_push_subscription_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: web_push_subscription_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.web_push_subscription_id_seq OWNED BY public.web_push_subscription.id;


--
-- Name: blocked_users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocked_users ALTER COLUMN id SET DEFAULT nextval('public.blocked_users_id_seq'::regclass);


--
-- Name: conversations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations ALTER COLUMN id SET DEFAULT nextval('public.conversations_id_seq'::regclass);


--
-- Name: fcm_token id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fcm_token ALTER COLUMN id SET DEFAULT nextval('public.fcm_token_id_seq'::regclass);


--
-- Name: friend_requests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friend_requests ALTER COLUMN id SET DEFAULT nextval('public.friend_requests_id_seq'::regclass);


--
-- Name: key_bundles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.key_bundles ALTER COLUMN id SET DEFAULT nextval('public.key_bundles_id_seq'::regclass);


--
-- Name: messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages ALTER COLUMN id SET DEFAULT nextval('public.messages_id_seq'::regclass);


--
-- Name: one_time_pre_keys id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.one_time_pre_keys ALTER COLUMN id SET DEFAULT nextval('public.one_time_pre_keys_id_seq'::regclass);


--
-- Name: secret_notes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.secret_notes ALTER COLUMN id SET DEFAULT nextval('public.secret_notes_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: web_push_subscription id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.web_push_subscription ALTER COLUMN id SET DEFAULT nextval('public.web_push_subscription_id_seq'::regclass);


--
-- Name: web_push_subscription PK_08337e9e8b3ca6f53c3d9591116; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.web_push_subscription
    ADD CONSTRAINT "PK_08337e9e8b3ca6f53c3d9591116" PRIMARY KEY (id);


--
-- Name: messages PK_18325f38ae6de43878487eff986; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT "PK_18325f38ae6de43878487eff986" PRIMARY KEY (id);


--
-- Name: friend_requests PK_3827ba86ce64ecb4b90c92eeea6; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friend_requests
    ADD CONSTRAINT "PK_3827ba86ce64ecb4b90c92eeea6" PRIMARY KEY (id);


--
-- Name: key_bundles PK_5b78fed9cecdc31e7c143d2506f; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.key_bundles
    ADD CONSTRAINT "PK_5b78fed9cecdc31e7c143d2506f" PRIMARY KEY (id);


--
-- Name: refresh_tokens PK_7d8bee0204106019488c4c50ffa; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT "PK_7d8bee0204106019488c4c50ffa" PRIMARY KEY (id);


--
-- Name: blocked_users PK_93760d788a31b7546c5424f42cc; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocked_users
    ADD CONSTRAINT "PK_93760d788a31b7546c5424f42cc" PRIMARY KEY (id);


--
-- Name: one_time_pre_keys PK_9fbbe6e24175b0183706f33e8d0; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.one_time_pre_keys
    ADD CONSTRAINT "PK_9fbbe6e24175b0183706f33e8d0" PRIMARY KEY (id);


--
-- Name: users PK_a3ffb1c0c8416b9fc6f907b7433; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT "PK_a3ffb1c0c8416b9fc6f907b7433" PRIMARY KEY (id);


--
-- Name: secret_notes PK_d756ee4a462586aaca184e13448; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.secret_notes
    ADD CONSTRAINT "PK_d756ee4a462586aaca184e13448" PRIMARY KEY (id);


--
-- Name: fcm_token PK_ec8f7ff07f44545126442edd9e7; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fcm_token
    ADD CONSTRAINT "PK_ec8f7ff07f44545126442edd9e7" PRIMARY KEY (id);


--
-- Name: conversations PK_ee34f4f7ced4ec8681f26bf04ef; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT "PK_ee34f4f7ced4ec8681f26bf04ef" PRIMARY KEY (id);


--
-- Name: secret_notes UQ_1be15e9be1d0b4598d19b96790c; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.secret_notes
    ADD CONSTRAINT "UQ_1be15e9be1d0b4598d19b96790c" UNIQUE (token);


--
-- Name: fcm_token UQ_443f8d9334e75b1e2ec1312d114; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fcm_token
    ADD CONSTRAINT "UQ_443f8d9334e75b1e2ec1312d114" UNIQUE (token);


--
-- Name: web_push_subscription UQ_7103f32a09826244a9378ac68dd; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.web_push_subscription
    ADD CONSTRAINT "UQ_7103f32a09826244a9378ac68dd" UNIQUE (endpoint);


--
-- Name: users UQ_82ed9e04d0b61a87074cf8a8d39; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT "UQ_82ed9e04d0b61a87074cf8a8d39" UNIQUE (username, tag);


--
-- Name: key_bundles UQ_df7487788fe52280ea907489c1f; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.key_bundles
    ADD CONSTRAINT "UQ_df7487788fe52280ea907489c1f" UNIQUE ("userId");


--
-- Name: IDX_443f8d9334e75b1e2ec1312d11; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_443f8d9334e75b1e2ec1312d11" ON public.fcm_token USING btree (token);


--
-- Name: IDX_4c33ef2d7043d4b1b3142a4985; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_4c33ef2d7043d4b1b3142a4985" ON public.friend_requests USING btree (sender_id, receiver_id);


--
-- Name: IDX_621544c9687b4b438d203bb57f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "IDX_621544c9687b4b438d203bb57f" ON public.one_time_pre_keys USING btree ("userId", used);


--
-- Name: IDX_7103f32a09826244a9378ac68d; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_7103f32a09826244a9378ac68d" ON public.web_push_subscription USING btree (endpoint);


--
-- Name: IDX_a7838d2ba25be1342091b6695f; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_a7838d2ba25be1342091b6695f" ON public.refresh_tokens USING btree (token_hash);


--
-- Name: IDX_b67ed0acca994276b01f268843; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX "IDX_b67ed0acca994276b01f268843" ON public.blocked_users USING btree (blocker_id, blocked_id);


--
-- Name: idx_messages_conv_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_messages_conv_created ON public.messages USING btree (conversation_id, "createdAt");


--
-- Name: messages FK_22133395bd13b970ccd0c34ab22; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT "FK_22133395bd13b970ccd0c34ab22" FOREIGN KEY (sender_id) REFERENCES public.users(id);


--
-- Name: messages FK_3bc55a7c3f9ed54b520bb5cfe23; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT "FK_3bc55a7c3f9ed54b520bb5cfe23" FOREIGN KEY (conversation_id) REFERENCES public.conversations(id);


--
-- Name: refresh_tokens FK_3ddc983c5f7bcf132fd8732c3f4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT "FK_3ddc983c5f7bcf132fd8732c3f4" FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: conversations FK_4c22a9bfb8f140d539970ba33d7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT "FK_4c22a9bfb8f140d539970ba33d7" FOREIGN KEY (user_two_id) REFERENCES public.users(id);


--
-- Name: friend_requests FK_781744f1014838837741581a8b7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friend_requests
    ADD CONSTRAINT "FK_781744f1014838837741581a8b7" FOREIGN KEY (receiver_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: blocked_users FK_7e543cda1c6f5aa2034fd2c105d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocked_users
    ADD CONSTRAINT "FK_7e543cda1c6f5aa2034fd2c105d" FOREIGN KEY (blocker_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: messages FK_7f87cbb925b1267778a7f4c5d67; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT "FK_7f87cbb925b1267778a7f4c5d67" FOREIGN KEY (reply_to_message_id) REFERENCES public.messages(id);


--
-- Name: conversations FK_830884f45056ea26f750cd95dd2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT "FK_830884f45056ea26f750cd95dd2" FOREIGN KEY (user_one_id) REFERENCES public.users(id);


--
-- Name: friend_requests FK_c034dd387df6cd4ce9aaebdd480; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friend_requests
    ADD CONSTRAINT "FK_c034dd387df6cd4ce9aaebdd480" FOREIGN KEY (sender_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: blocked_users FK_f515c19546d94b927811b9b3f15; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocked_users
    ADD CONSTRAINT "FK_f515c19546d94b927811b9b3f15" FOREIGN KEY (blocked_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict QdBeEoJl9FD5x5ZPxpr9zMBVsOiYxpN3uo2dO7SWucLM0o4AEHhD7aF2k8GZmny

