# Portions of this file are derived from Pleroma:
# Copyright © 2017-2018 Pleroma Authors <https://pleroma.social>
# SPDX-License-Identifier: AGPL-3.0-only
# Upstream: https://git.pleroma.social/pleroma/pleroma/blob/develop/lib/pleroma/web/activity_pub/utils.ex

defmodule Mobilizon.Service.ActivityPub.Utils do
  @moduledoc """
  # Utils

  Various utils
  """

  alias Mobilizon.Repo
  alias Mobilizon.Actors
  alias Mobilizon.Actors.Actor
  alias Mobilizon.Events.Event
  alias Mobilizon.Events.Comment
  alias Mobilizon.Events
  alias Mobilizon.Activity
  alias Mobilizon.Service.ActivityPub
  alias Ecto.Changeset
  require Logger

  # Some implementations send the actor URI as the actor field, others send the entire actor object,
  # so figure out what the actor's URI is based on what we have.
  def get_url(object) do
    case object do
      %{"id" => id} -> id
      id -> id
    end
  end

  def make_json_ld_header do
    %{
      "@context" => [
        "https://www.w3.org/ns/activitystreams",
        "https://litepub.github.io/litepub/context.jsonld",
        %{
          "sc" => "http://schema.org#",
          "Hashtag" => "as:Hashtag",
          "category" => "sc:category",
          "uuid" => "sc:identifier"
        }
      ]
    }
  end

  def make_date do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  @doc """
  Enqueues an activity for federation if it's local
  """
  def maybe_federate(%Activity{local: true} = activity) do
    Logger.debug("Maybe federate an activity")

    priority =
      case activity.data["type"] do
        "Delete" -> 10
        "Create" -> 1
        _ -> 5
      end

    Mobilizon.Service.Federator.enqueue(:publish, activity, priority)
    :ok
  end

  def maybe_federate(_), do: :ok

  def remote_actors(%{data: %{"to" => to} = data}) do
    to = to ++ (data["cc"] || [])

    to
    |> Enum.map(fn url -> Actors.get_actor_by_url(url) end)
    |> Enum.map(fn {status, actor} ->
      case status do
        :ok ->
          actor

        _ ->
          nil
      end
    end)
    |> Enum.map(& &1)
    |> Enum.filter(fn actor -> actor && !is_nil(actor.domain) end)
  end

  @doc """
  Adds an id and a published data if they aren't there,
  also adds it to an included object
  """
  def lazy_put_activity_defaults(map) do
    if is_map(map["object"]) do
      object = lazy_put_object_defaults(map["object"])
      %{map | "object" => object}
    else
      map
    end
  end

  @doc """
  Adds an id and published date if they aren't there.
  """
  def lazy_put_object_defaults(map) do
    Map.put_new_lazy(map, "published", &make_date/0)
  end

  @doc """
  Converts an AP object data to our internal data structure
  """
  def object_to_event_data(object) do
    {:ok, %Actor{id: actor_id}} = Actors.get_actor_by_url(object["actor"])

    %{
      "title" => object["name"],
      "description" => object["content"],
      "organizer_actor_id" => actor_id,
      "begins_on" => object["begins_on"],
      "category_id" => Events.get_category_by_title(object["category"]).id,
      "url" => object["id"],
      "uuid" => object["uuid"]
    }
  end

  @doc """
  Inserts a full object if it is contained in an activity.
  """
  def insert_full_object(object_data)

  @doc """
  Inserts a full object if it is contained in an activity.
  """
  def insert_full_object(%{"object" => %{"type" => "Event"} = object_data})
      when is_map(object_data) do
    with object_data <- object_to_event_data(object_data),
         {:ok, _} <- Events.create_event(object_data) do
      :ok
    end
  end

  def insert_full_object(%{"object" => %{"type" => "Group"} = object_data})
      when is_map(object_data) do
    with object_data <-
           Map.put(object_data, "preferred_username", object_data["preferredUsername"]),
         {:ok, _} <- Actors.create_group(object_data) do
      :ok
    end
  end

  @doc """
  Inserts a full object if it is contained in an activity.
  """
  def insert_full_object(%{"object" => %{"type" => "Note"} = object_data})
      when is_map(object_data) do
    Logger.debug("Inserting full comment")
    Logger.debug(inspect(object_data))

    with {:ok, %Actor{id: actor_id}} <- Actors.get_or_fetch_by_url(object_data["actor"]) do
      data = %{
        "text" => object_data["content"],
        "url" => object_data["id"],
        "actor_id" => actor_id,
        "in_reply_to_comment_id" => nil,
        "event_id" => nil,
        "uuid" => object_data["uuid"]
      }

      # We fetch the parent object
      Logger.debug("We're fetching the parent object")

      data =
        if Map.has_key?(object_data, "inReplyTo") && object_data["inReplyTo"] != nil &&
             object_data["inReplyTo"] != "" do
          Logger.debug(fn -> "Object has inReplyTo #{object_data["inReplyTo"]}" end)

          case ActivityPub.fetch_object_from_url(object_data["inReplyTo"]) do
            # Reply to an event (Comment)
            {:ok, %Event{id: id}} ->
              Logger.debug("Parent object is an event")
              data |> Map.put("event_id", id)

            # Reply to a comment (Comment)
            {:ok, %Comment{id: id} = comment} ->
              Logger.debug("Parent object is another comment")

              data
              |> Map.put("in_reply_to_comment_id", id)
              |> Map.put("origin_comment_id", comment |> Comment.get_thread_id())

            # Anything else is kind of a MP
            {:error, object} ->
              Logger.debug("Parent object is something we don't handle")
              Logger.debug(inspect(object))
              data
          end
        else
          Logger.debug("No parent object for this comment")
          data
        end

      with {:ok, _comment} <- Events.create_comment(data) do
        :ok
      else
        err ->
          Logger.error("Error while inserting a remote comment inside database")
          Logger.error(inspect(err))
          {:error, err}
      end
    end
  end

  def insert_full_object(_), do: :ok

  #### Like-related helpers

  #  @doc """
  #  Returns an existing like if a user already liked an object
  #  """
  #  def get_existing_like(actor, %{data: %{"id" => id}}) do
  #    query =
  #      from(
  #        activity in Activity,
  #        where: fragment("(?)->>'actor' = ?", activity.data, ^actor),
  #        # this is to use the index
  #        where:
  #          fragment(
  #            "coalesce((?)->'object'->>'id', (?)->>'object') = ?",
  #            activity.data,
  #            activity.data,
  #            ^id
  #          ),
  #        where: fragment("(?)->>'type' = 'Like'", activity.data)
  #      )
  #
  #    Repo.one(query)
  #  end

  @doc """
  Make an AP event object from an set of values
  """
  @spec make_event_data(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          list(),
          list(),
          map(),
          String.t()
        ) :: map()
  def make_event_data(
        actor,
        to,
        title,
        content_html,
        # attachments,
        tags \\ [],
        # _cw \\ nil,
        cc \\ [],
        metadata \\ %{},
        category \\ ""
      ) do
    Logger.debug("Making event data")
    uuid = Ecto.UUID.generate()

    %{
      "type" => "Event",
      "to" => to,
      "cc" => cc,
      "content" => content_html,
      "name" => title,
      # "summary" => cw,
      # "attachment" => attachments,
      "begins_on" => metadata.begins_on,
      "category" => category,
      "actor" => actor,
      "id" => "#{MobilizonWeb.Endpoint.url()}/events/#{uuid}",
      "uuid" => uuid,
      "tag" => tags |> Enum.map(fn {_, tag} -> tag end) |> Enum.uniq()
    }
  end

  @spec make_event_data(Event.t(), list(String.t())) :: map()
  def make_event_data(
        %Event{title: title, organizer_actor: actor, uuid: uuid},
        to \\ ["https://www.w3.org/ns/activitystreams#Public"]
      ) do
    %{
      "type" => "Event",
      "to" => to,
      "title" => title,
      "actor" => actor.url,
      "uuid" => uuid,
      "id" => "#{MobilizonWeb.Endpoint.url()}/events/#{uuid}"
    }
  end

  @doc """
  Make an AP comment object from an existing `Comment` structure.
  """
  def make_comment_data(
        %Comment{
          text: text,
          actor: actor,
          uuid: uuid,
          in_reply_to_comment: reply_to,
          event: event
        },
        to \\ ["https://www.w3.org/ns/activitystreams#Public"]
      ) do
    object = %{
      "type" => "Note",
      "to" => to,
      "content" => text,
      "actor" => actor.url,
      "attributedTo" => actor.url,
      "uuid" => uuid,
      "id" => "#{MobilizonWeb.Endpoint.url()}/comments/#{uuid}"
    }

    if reply_to do
      object |> Map.put("inReplyTo", reply_to.url || event.url)
    else
      object
    end
  end

  @doc """
  Make an AP comment object from an set of values
  """
  def make_comment_data(
        actor,
        to,
        content_html,
        # attachments,
        inReplyTo \\ nil,
        tags \\ [],
        # _cw \\ nil,
        cc \\ []
      ) do
    Logger.debug("Making comment data")
    uuid = Ecto.UUID.generate()

    object = %{
      "type" => "Note",
      "to" => to,
      "cc" => cc,
      "content" => content_html,
      # "summary" => cw,
      # "attachment" => attachments,
      "actor" => actor,
      "id" => "#{MobilizonWeb.Endpoint.url()}/comments/#{uuid}",
      "uuid" => uuid,
      "tag" => tags |> Enum.map(fn {_, tag} -> tag end) |> Enum.uniq()
    }

    if inReplyTo do
      object
      |> Map.put("inReplyTo", inReplyTo)
    else
      object
    end
  end

  def make_group_data(
        actor,
        to,
        preferred_username,
        content_html,
        # attachments,
        tags \\ [],
        # _cw \\ nil,
        cc \\ []
      ) do
    uuid = Ecto.UUID.generate()

    %{
      "type" => "Group",
      "to" => to,
      "cc" => cc,
      "summary" => content_html,
      "attributedTo" => actor,
      "preferredUsername" => preferred_username,
      "id" => "#{MobilizonWeb.Endpoint.url()}/~#{preferred_username}",
      "uuid" => uuid,
      "tag" => tags |> Enum.map(fn {_, tag} -> tag end) |> Enum.uniq()
    }
  end

  #### Like-related helpers

  @doc """
  Returns an existing like if a user already liked an object
  """
  # @spec get_existing_like(Actor.t, map()) :: nil
  # def get_existing_like(%Actor{url: url} = actor, %{data: %{"id" => id}}) do
  #   nil
  # end

  # def make_like_data(%Actor{url: url} = actor, %{data: %{"id" => id}} = object, activity_id) do
  #   data = %{
  #     "type" => "Like",
  #     "actor" => url,
  #     "object" => id,
  #     "to" => [actor.followers_url, object.data["actor"]],
  #     "cc" => ["https://www.w3.org/ns/activitystreams#Public"],
  #     "context" => object.data["context"]
  #   }

  #   if activity_id, do: Map.put(data, "id", activity_id), else: data
  # end

  def update_element_in_object(property, element, object) do
    with new_data <-
           object.data
           |> Map.put("#{property}_count", length(element))
           |> Map.put("#{property}s", element),
         changeset <- Changeset.change(object, data: new_data),
         {:ok, object} <- Repo.update(changeset) do
      {:ok, object}
    end
  end

  #  def update_likes_in_object(likes, object) do
  #    update_element_in_object("like", likes, object)
  #  end
  #
  #  def add_like_to_object(%Activity{data: %{"actor" => actor}}, object) do
  #    with likes <- [actor | object.data["likes"] || []] |> Enum.uniq() do
  #      update_likes_in_object(likes, object)
  #    end
  #  end
  #
  #  def remove_like_from_object(%Activity{data: %{"actor" => actor}}, object) do
  #    with likes <- (object.data["likes"] || []) |> List.delete(actor) do
  #      update_likes_in_object(likes, object)
  #    end
  #  end

  #### Follow-related helpers

  @doc """
  Makes a follow activity data for the given followed and follower
  """
  def make_follow_data(%Actor{url: followed_id}, %Actor{url: follower_id}, activity_id) do
    Logger.debug("Make follow data")

    data = %{
      "type" => "Follow",
      "actor" => follower_id,
      "to" => [followed_id],
      "cc" => ["https://www.w3.org/ns/activitystreams#Public"],
      "object" => followed_id
    }

    Logger.debug(inspect(data))

    if activity_id,
      do: Map.put(data, "id", activity_id),
      else: data
  end

  #### Announce-related helpers

  @doc """
  Make announce activity data for the given actor and object
  """
  def make_announce_data(
        %Actor{url: actor_url} = actor,
        %Event{url: event_url} = object,
        activity_id
      ) do
    data = %{
      "type" => "Announce",
      "actor" => actor_url,
      "object" => event_url,
      "to" => [actor.followers_url, object.actor.url],
      "cc" => ["https://www.w3.org/ns/activitystreams#Public"]
      # "context" => object.data["context"]
    }

    if activity_id, do: Map.put(data, "id", activity_id), else: data
  end

  @doc """
  Make announce activity data for the given actor and object
  """
  def make_announce_data(
        %Actor{url: actor_url} = actor,
        %Comment{url: comment_url} = object,
        activity_id
      ) do
    data = %{
      "type" => "Announce",
      "actor" => actor_url,
      "object" => comment_url,
      "to" => [actor.followers_url, object.actor.url],
      "cc" => ["https://www.w3.org/ns/activitystreams#Public"]
      # "context" => object.data["context"]
    }

    if activity_id, do: Map.put(data, "id", activity_id), else: data
  end

  def add_announce_to_object(%Activity{data: %{"actor" => actor}}, object) do
    with announcements <- [actor | object.data["announcements"] || []] |> Enum.uniq() do
      update_element_in_object("announcement", announcements, object)
    end
  end

  #### Unfollow-related helpers

  @spec make_unfollow_data(Actor.t(), Actor.t(), map(), String.t()) :: map()
  def make_unfollow_data(
        %Actor{url: follower_url},
        %Actor{url: followed_url},
        follow_activity,
        activity_id
      ) do
    data = %{
      "type" => "Undo",
      "actor" => follower_url,
      "to" => [followed_url],
      "object" => follow_activity.data
    }

    if activity_id, do: Map.put(data, "id", activity_id), else: data
  end

  #### Create-related helpers

  @doc """
  Make create activity data
  """
  @spec make_create_data(map(), map()) :: map()
  def make_create_data(params, additional \\ %{}) do
    Logger.debug("Making create data")
    Logger.debug(inspect(params))
    published = params.published || make_date()

    %{
      "type" => "Create",
      "to" => params.to |> Enum.uniq(),
      "actor" => params.actor.url,
      "object" => params.object,
      "published" => published
    }
    |> Map.merge(additional)
  end

  @doc """
  Converts PEM encoded keys to a public key representation
  """
  def pem_to_public_key(pem) do
    [key_code] = :public_key.pem_decode(pem)
    key = :public_key.pem_entry_decode(key_code)

    case key do
      {:RSAPrivateKey, _, modulus, exponent, _, _, _, _, _, _, _} ->
        {:RSAPublicKey, modulus, exponent}

      {:RSAPublicKey, modulus, exponent} ->
        {:RSAPublicKey, modulus, exponent}
    end
  end

  @doc """
  Converts PEM encoded keys to a private key representation
  """
  def pem_to_private_key(pem) do
    [private_key_code] = :public_key.pem_decode(pem)
    :public_key.pem_entry_decode(private_key_code)
  end

  @doc """
  Converts PEM encoded keys to a PEM public key representation
  """
  def pem_to_public_key_pem(pem) do
    public_key = pem_to_public_key(pem)
    public_key = :public_key.pem_entry_encode(:RSAPublicKey, public_key)
    :public_key.pem_encode([public_key])
  end
end
