// This file is part of MusicBrainz, the open internet music database.
// Copyright (C) 2015 MetaBrainz Foundation
// Licensed under the GPL version 2, or (at your option) any later version:
// http://www.gnu.org/licenses/gpl-2.0.txt

const _ = require('lodash');
const React = require('react');

const EditorLink = require('../../static/scripts/common/components/EditorLink');
const {VARTIST_GID} = require('../../static/scripts/common/constants');
const {l, lp} = require('../../static/scripts/common/i18n');

function languageLink(language) {
  let {id, native_language, native_territory} = language[1];
  let text = `[${id}]`;

  if (native_language) {
    text = _.capitalize(native_language);

    if (native_territory) {
      text += ' (' + _.capitalize(native_territory) + ')';
    }
  }

  return (
    <a href={"/set-language/" + encodeURIComponent(language[0])}>
      {text}
    </a>
  );
}

function userLink(userName, path) {
  return `/user/${encodeURIComponent(userName)}${path}`;
}

const LanguageMenu = () => (
  <li className="language-selector">
    {languageLink(_.find($c.stash.server_languages, l => l[0] === $c.stash.current_language))}
    <ul>
      {$c.stash.server_languages.map(function (l, index) {
        let inner = languageLink(l);

        if (l[0] === $c.stash.current_language) {
          inner = <strong>{inner}</strong>;
        }

        return <li key={index}>{inner}</li>;
      })}
      <li>
        <a href="/set-language/unset">
          {l('(reset language)')}
        </a>
      </li>
      <li className="separator">
        <a href="https://www.transifex.com/musicbrainz/musicbrainz/">
          {l('Help Translate')}
        </a>
      </li>
    </ul>
  </li>
);

const AccountMenu = () => (
  <li className="account">
    <EditorLink editor={$c.user} />
    <ul>
      <li>
        <a href="/account/edit">{l('Edit Profile')}</a>
      </li>
      <li>
        <a href="/account/change-password">{l('Change Password')}</a>
      </li>
      <li>
        <a href="/account/preferences">{l('Preferences')}</a>
      </li>
      <li>
        <a href="/account/applications">{l('Applications')}</a>
      </li>
      <li>
        <a href={userLink($c.user.name, '/subscriptions/artist')}>
          {l('Subscriptions')}
        </a>
      </li>
      <li>
        <a href="/logout">{l('Log Out')}</a>
      </li>
    </ul>
  </li>
);

const DataMenu = () => {
  let userName = $c.user.name;

  return (
    <li className="data">
      <a href={userLink(userName, '/profile')}>{l('My Data')}</a>
      <ul>
        <li>
          <a href={userLink(userName, '/collections')}>{l('My Collections')}</a>
        </li>
        <li>
          <a href={userLink(userName, '/ratings')}>{l('My Ratings')}</a>
        </li>
        <li>
          <a href={userLink(userName, '/tags')}>{l('My Tags')}</a>
        </li>
        <li className="separator">
          <a href={userLink(userName, '/edits/open')}>{l('My Open Edits')}</a>
        </li>
        <li>
          <a href={userLink(userName, '/edits/all')}>{l('All My Edits')}</a>
        </li>
        <li>
          <a href="/edit/subscribed">{l('Edits for Subscribed Entities')}</a>
        </li>
        <li>
          <a href="/edit/subscribed_editors">{l('Edits by Subscribed Editors')}</a>
        </li>
        <li>
          <a href="/edit/notes-received">{l('Notes Left on My Edits')}</a>
        </li>
      </ul>
    </li>
  );
};

const AdminMenu = () => (
  <li className="admin">
    <a href="/admin">{l('Admin')}</a>
    <ul>
      {$c.user.is_location_editor &&
        <li>
          <a href="/area/create">{lp('Add Area', 'button/menu')}</a>
        </li>}

      {$c.user.is_relationship_editor && [
        <li key="1">
          <a href="/instrument/create">{lp('Add Instrument', 'button/menu')}</a>
        </li>,
        <li key="2">
          <a href="/relationships">{l('Edit Relationship Types')}</a>
        </li>]}

      {$c.user.is_wiki_transcluder &&
        <li>
          <a href="/admin/wikidoc">{l('Transclude WikiDocs')}</a>
        </li>}

      {$c.user.is_banner_editor &&
        <li>
          <a href="/admin/banner/edit">{l('Edit Banner Message')}</a>
        </li>}

      {$c.user.is_account_admin &&
        <li>
          <a href="/admin/attributes">{l('Edit Attributes')}</a>
        </li>}
    </ul>
  </li>
);

const AboutMenu = () => (
  <li className="about">
    <a href="/doc/About">{l('About')}</a>
    <ul>
      <li>
        <a href="//metabrainz.org/doc/Sponsors">{l('Sponsors')}</a>
      </li>
      <li>
        <a href="/doc/About/Team">{l('Team')}</a>
      </li>
      <li className="separator">
        <a href="/doc/About/Data_License">{l('Data Licenses')}</a>
      </li>
      <li>
        <a href="/doc/Social_Contract">{l('Social Contract')}</a>
      </li>
      <li>
        <a href="/doc/Code_of_Conduct">{l('Code of Conduct')}</a>
      </li>
      <li>
        <a href="/doc/About/Privacy_Policy">{l('Privacy Policy')}</a>
      </li>
      <li className="separator">
        <a href="/elections">{l('Auto-editor Elections')}</a>
      </li>
      <li>
        <a href="/privileged">{l('Privileged User Accounts')}</a>
      </li>
      <li>
        <a href="/statistics">{l('Statistics')}</a>
      </li>
      <li>
        <a href="/statistics/timeline">{l('Timeline Graph')}</a>
      </li>
    </ul>
  </li>
);

const BlogMenu = () => (
  <li className="blog">
    <a href="http://blog.musicbrainz.org" className="internal">
      {l('Blog')}
    </a>
  </li>
);

const ProductsMenu = () => (
  <li className="products">
    <a href="/doc/Products">{l('Products')}</a>
    <ul>
      <li>
        <a href="//picard.musicbrainz.org">{l('MusicBrainz Picard')}</a>
      </li>
      <li>
        <a href="/doc/Magic_MP3_Tagger">{l('Magic MP3 Tagger')}</a>
      </li>
      <li>
        <a href="/doc/Yate_Music_Tagger">{l('Yate Music Tagger')}</a>
      </li>
      <li className="separator">
        <a href="/doc/MusicBrainz_for_Android">{l('MusicBrainz for Android')}</a>
      </li>
      <li className="separator">
        <a href="/doc/MusicBrainz_Server">{l('MusicBrainz Server')}</a>
      </li>
      <li>
        <a href="/doc/MusicBrainz_Database">{l('MusicBrainz Database')}</a>
      </li>
      <li className="separator">
        <a href="/doc/Developer_Resources">{l('Developer Resources')}</a>
      </li>
      <li>
        <a href="/doc/XML_Web_Service">{l('XML Web Service')}</a>
      </li>
      <li>
        <a href="/doc/Live_Data_Feed">{l('Live Data Feed')}</a>
      </li>
      <li className="separator">
        <a href="/doc/FreeDB_Gateway">{l('FreeDB Gateway')}</a>
      </li>
    </ul>
  </li>
);

const SearchMenu = () => (
  <li className="search">
    <a href="/search">{l('Search')}</a>
    <ul>
      {$c.user &&
        <li>
          <a href="/search/edits">{l('Search Edits')}</a>
        </li>}
      <li>
        <a href="/tags">{l('Tags')}</a>
      </li>
      <li>
        <a href="/cdstub/browse">{l('Top CD Stubs')}</a>
      </li>
    </ul>
  </li>
);

const EditingMenu = () => (
  <li className="editing">
    <a href="/doc/How_Editing_Works">{l('Editing')}</a>
    <ul>
      <li>
        <a href="/artist/create">{lp('Add Artist', 'button/menu')}</a>
      </li>
      <li>
        <a href="/label/create">{lp('Add Label', 'button/menu')}</a>
      </li>
      <li>
        <a href="/release-group/create">{lp('Add Release Group', 'button/menu')}</a>
      </li>
      <li>
        <a href="/release/add">{lp('Add Release', 'button/menu')}</a>
      </li>
      <li>
        <a href={"/release/add?artist=" + encodeURIComponent(VARTIST_GID)}>
          {l('Add Various Artists Release')}
        </a>
      </li>
      <li>
        <a href="/recording/create">{lp('Add Standalone Recording', 'button/menu')}</a>
      </li>
      <li>
        <a href="/work/create">{lp('Add Work', 'button/menu')}</a>
      </li>
      <li>
        <a href="/place/create">{lp('Add Place', 'button/menu')}</a>
      </li>
      <li>
        <a href="/series/create">{lp('Add Series', 'button/menu')}</a>
      </li>
      <li>
        <a href="/event/create">{lp('Add Event', 'button/menu')}</a>
      </li>
      <li className="separator">
        <a href="/edit/open">{l('Vote on Edits')}</a>
      </li>
      <li>
        <a href="/reports">{l('Reports')}</a>
      </li>
    </ul>
  </li>
);

const DocumentationMenu = () => (
  <li className="documentation">
    <a href="/doc/MusicBrainz_Documentation">{l('Documentation')}</a>
    <ul>
      <li>
        <a href="/doc/Beginners_Guide">{l('Beginners Guide')}</a>
      </li>
      <li>
        <a href="/doc/Style">{l('Style Guidelines')}</a>
      </li>
      <li>
        <a href="/doc/How_To">{l('How Tos')}</a>
      </li>
      <li>
        <a href="/doc/Frequently_Asked_Questions">{l('FAQs')}</a>
      </li>
      <li className="separator">
        <a href='/doc/Edit_Types'>{l('Edit Types')}</a>
      </li>
      <li>
        <a href="/relationships">{l('Relationship Types')}</a>
      </li>
      <li>
        <a href="/instruments">{l('Instrument List')}</a>
      </li>
      <li className="separator">
        <a href="/doc/Development">{l('Development')}</a>
      </li>
    </ul>
  </li>
);

const ContactMenu = () => (
  <li className="contact">
    <a href="https://metabrainz.org/contact">{l('Contact Us')}</a>
    <ul>
      <li>
        <a href="http://forums.musicbrainz.org" className="internal">
          {l('Forums')}
        </a>
      </li>
      <li>
        <a href="http://tickets.musicbrainz.org" className="internal">
          {l('Report a Bug')}
        </a>
      </li>
    </ul>
  </li>
);

const LeftMenu = () => (
  <ul>
    <AboutMenu />
    <BlogMenu />
    <ProductsMenu />
    <SearchMenu />
    {$c.user && <EditingMenu />}
    <DocumentationMenu />
    <ContactMenu />
  </ul>
);

const RightMenu = (props) => (
  <ul className="r">
    {$c.stash.server_languages.length > 1 && <LanguageMenu />}

    {$c.user && [
      <AccountMenu key={1} />,
      <DataMenu key={2} />,
      $c.user.is_admin && <AdminMenu key={3} />
    ]}

    {!$c.user && [
      <li key={4}>
        <a href={"/login?uri=" + encodeURIComponent($c.req.query_params.uri || $c.relative_uri)}>
          {l('Log In')}
        </a>
      </li>,
      <li key={5}>
        <a href={"/register?uri=" + encodeURIComponent($c.req.query_params.uri || $c.relative_uri)}>
          {l('Create Account')}
        </a>
      </li>
    ]}
  </ul>
);

const Menu = () => (
  <div id="header-menu">
    <div>
      <RightMenu />
      <LeftMenu />
    </div>
  </div>
);

module.exports = Menu;