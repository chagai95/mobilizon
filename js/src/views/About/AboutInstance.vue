<template>
  <div v-if="config">
    <section class="hero is-primary">
      <div class="hero-body">
        <div class="container">
          <h2 class="title">{{ config.name }}</h2>
          <p>{{ config.description }}</p>
        </div>
      </div>
    </section>
    <section class="columns contact-statistics" v-if="statistics">
      <div class="column is-three-quarters-desktop statistics">
        <i18n tag="p" path="Home to {number} users">
          <strong slot="number">{{ statistics.numberOfUsers }}</strong>
        </i18n>
        <i18n tag="p" path="and {number} groups">
          <strong slot="number">{{ statistics.numberOfLocalGroups }}</strong>
        </i18n>
        <i18n tag="p" path="Who published {number} events">
          <strong slot="number">{{ statistics.numberOfLocalEvents }}</strong>
        </i18n>
        <i18n tag="p" path="And {number} comments">
          <strong slot="number">{{ statistics.numberOfLocalComments }}</strong>
        </i18n>
      </div>
      <div class="column contact">
        <h4>{{ $t("Contact") }}</h4>
        <p>
          <a
            :title="config.contact"
            v-if="generateConfigLink()"
            :href="generateConfigLink().uri"
            >{{ generateConfigLink().text }}</a
          >
          <span v-else-if="config.contact">{{ config.contact }}</span>
          <span v-else>{{ $t("contact uninformed") }}</span>
        </p>
      </div>
    </section>
    <hr />
    <section class="long-description content">
      <div v-html="config.longDescription" />
    </section>
    <hr />
    <section class="config">
      <h3 class="subtitle">{{ $t("Instance configuration") }}</h3>
      <table class="table is-fullwidth">
        <tr>
          <td>{{ $t("Instance languages") }}</td>
          <td :title="this.config ? this.config.languages.join(', ') : ''">
            {{ formattedLanguageList }}
          </td>
        </tr>
        <tr>
          <td>{{ $t("Mobilizon version") }}</td>
          <td>{{ config.version }}</td>
        </tr>
        <tr>
          <td>{{ $t("Registrations") }}</td>
          <td v-if="config.registrationsOpen && config.registrationsAllowlist">
            {{ $t("Restricted") }}
          </td>
          <td v-if="config.registrationsOpen && !config.registrationsAllowlist">
            {{ $t("Open") }}
          </td>
          <td v-else>{{ $t("Closed") }}</td>
        </tr>
        <tr>
          <td>{{ $t("Federation") }}</td>
          <td v-if="config.federating">{{ $t("Enabled") }}</td>
          <td v-else>{{ $t("Disabled") }}</td>
        </tr>
        <tr>
          <td>{{ $t("Anonymous participations") }}</td>
          <td v-if="config.anonymous.participation.allowed">
            {{ $t("If allowed by organizer") }}
          </td>
          <td v-else>{{ $t("Disabled") }}</td>
        </tr>
      </table>
    </section>
  </div>
</template>

<script lang="ts">
import { Component, Vue } from "vue-property-decorator";
import { formatList } from "@/utils/i18n";
import { LANGUAGES_CODES } from "@/graphql/admin";
import { ILanguage } from "@/types/admin.model";
import { ABOUT } from "../../graphql/config";
import { STATISTICS } from "../../graphql/statistics";
import { IConfig } from "../../types/config.model";
import { IStatistics } from "../../types/statistics.model";
import langs from "../../i18n/langs.json";

@Component({
  apollo: {
    config: ABOUT,
    statistics: STATISTICS,
    languages: {
      query: LANGUAGES_CODES,
      variables() {
        return {
          codes: this.config.languages,
        };
      },
      skip() {
        return !this.config || !this.config.languages;
      },
    },
  },
})
export default class AboutInstance extends Vue {
  config!: IConfig;

  statistics!: IStatistics;

  languages!: ILanguage[];

  get isContactEmail(): boolean {
    return this.config && this.config.contact.includes("@");
  }

  get isContactURL(): boolean {
    return this.config && this.config.contact.match(/^https?:\/\//g) !== null;
  }

  get formattedLanguageList(): string {
    if (this.languages) {
      const list = this.languages.map(({ name }) => name);
      return formatList(list);
    }
    return "";
  }

  // eslint-disable-next-line class-methods-use-this
  getLanguageNameForCode(code: string): string {
    const languageMaps = langs as Record<string, any>;
    return languageMaps[code];
  }

  generateConfigLink(): { uri: string; text: string } | null {
    if (!this.config.contact) return null;
    if (this.isContactEmail) {
      return {
        uri: `mailto:${this.config.contact}`,
        text: this.config.contact,
      };
    }
    if (this.isContactURL) {
      return {
        uri: this.config.contact,
        text:
          AboutInstance.urlToHostname(this.config.contact) ||
          (this.$t("Contact") as string),
      };
    }
    return null;
  }

  static urlToHostname(url: string): string | null {
    try {
      return new URL(url).hostname;
    } catch (e) {
      return null;
    }
  }
}
</script>

<style lang="scss" scoped>
section {
  &:not(:first-child) {
    margin: 2rem auto;
  }

  &.hero {
    h2.title {
      margin: auto;
    }
  }

  &.contact-statistics {
    margin: 2px auto;
    .statistics {
      display: grid;
      grid-template-columns: repeat(auto-fit, 150px);
      gap: 2rem 0;
      p {
        text-align: right;
        padding: 0 15px;

        & > * {
          display: block;
        }

        strong {
          font-weight: 500;
          font-size: 32px;
          line-height: 48px;
        }
      }
    }
    .contact {
      h4 {
        font-weight: bold;
      }
      p {
        width: 200px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
    }
  }
}
</style>
