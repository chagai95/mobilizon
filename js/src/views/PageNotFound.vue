<template>
  <section class="section container has-text-centered not-found">
    <div class="columns is-vertical is-centered">
      <div class="column is-half">
        <img
          src="/img/pics/2020-10-06-mobilizon-illustration-E_realisation.jpg"
          alt=""
        />
        <h1 class="title">
          {{ $t("The page you're looking for doesn't exist.") }}
        </h1>
        <p>
          {{
            $t(
              "Please make sure the address is correct and that the page hasn't been moved."
            )
          }}
        </p>
        <p>
          {{
            $t(
              "Please contact this instance's Mobilizon admin if you think this is a mistake."
            )
          }}
        </p>
        <!--  The following should just be replaced with the SearchField component but it fails for some reason  -->
        <form @submit="enter">
          <b-field class="search">
            <b-input
              expanded
              icon="magnify"
              type="search"
              :placeholder="searchPlaceHolder"
              v-model="searchText"
            />
            <p class="control">
              <button type="submit" class="button is-primary">
                {{ $t("Search") }}
              </button>
            </p>
          </b-field>
        </form>
      </div>
    </div>
  </section>
</template>
<script lang="ts">
import { Component, Vue } from "vue-property-decorator";
import BField from "buefy/src/components/field/Field.vue";
import RouteName from "../router/name";

@Component({
  components: {
    BField,
  },
})
export default class PageNotFound extends Vue {
  searchText = "";

  get searchPlaceHolder(): string {
    return this.$t("Search events, groups, etc.") as string;
  }

  async enter(): Promise<void> {
    await this.$router.push({
      name: RouteName.SEARCH,
      query: { term: this.searchText },
    });
  }
}
</script>
<style lang="scss">
.container.not-found {
  margin: auto;
  background: $white;

  img {
    margin-top: 3rem;
  }

  p {
    margin-bottom: 1em;
  }
}
</style>
