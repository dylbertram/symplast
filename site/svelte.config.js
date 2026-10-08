import adapter from '@sveltejs/adapter-static';

export default {
  kit: {
    adapter: adapter({ pages: '../dist/site', assets: '../dist/site' }),
    csp: {
      mode: 'hash',
      directives: {
        'default-src': ['none'],
        'script-src': ['self'],
        // Bits UI uses inline styles for its accessible tooltip content.
        'style-src': ['self', 'unsafe-inline'],
        'img-src': ['self'],
        'connect-src': ['self'],
        'base-uri': ['none'],
        'form-action': ['none']
      }
    }
  }
};
