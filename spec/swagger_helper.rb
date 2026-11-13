# frozen_string_literal: true

require 'spec_helper'

RSpec.configure do |config|
  # Specify a root folder where Swagger JSON files are generated
  # NOTE: If you're using the rswag-api to serve API descriptions, you'll need
  # to ensure that it's configured to serve Swagger from the same folder
  config.swagger_root = Rails.root.join('swagger').to_s

  # Define one or more Swagger documents and provide global metadata for each one
  # When you run the 'rswag:specs:swaggerize' rake task, the complete Swagger will
  # be generated at the provided relative path under swagger_root
  # By default, the operations defined in spec files are added to the first
  # document below. You can override this behavior by adding a swagger_doc tag to the
  # the root example_group in your specs, e.g. describe '...', swagger_doc: 'v2/swagger.json'
  config.swagger_docs = {
    'v1/swagger.yaml' => {
      openapi: '3.0.3',
      info: {
        title: 'API V1',
        version: 'v1'
      },
      paths: {},
      components: {
        schemas: {
          pagination: {
            type: :object,
            properties: {
              recordCount: { type: :integer },
              pageCount: { type: :integer },
              currentPage: { type: :integer },
              pageSize: { type: :integer }
            },
            required: %w[recordCount pageCount currentPage pageSize]
          },
          Order: {
            type: :object,
            properties: {
              id: {
                type: :integer
              },
              name: {
                type: :string,
                description: "name of the order's supplier (or stock)"
              },
              starts: {
                type: :string,
                format: 'date-time',
                description: 'when the order was opened'
              },
              ends: {
                type: :string,
                nullable: true,
                format: 'date-time',
                description: 'when the order will close or was closed'
              },
              boxfill: {
                type: :string,
                nullable: true,
                format: 'date-time',
                description: 'when the order will enter or entered the boxfill phase'
              },
              pickup: {
                type: :string,
                nullable: true,
                format: :date,
                description: 'pickup date'
              },
              is_open: {
                type: :boolean,
                description: 'if the order is currently open or not'
              },
              is_boxfill: {
                type: :boolean,
                description: 'if the order is currently in the boxfill phase or not'
              },
              state: {
                type: :string,
                enum: %w[open finished received closed]
              },
              supplier_id: {
                type: :integer,
                nullable: true,
                description: 'id of the supplier, or null for a stock order'
              },
              note: {
                type: :string,
                nullable: true
              },
              end_action: {
                type: :string,
                enum: %w[no_end_action auto_close auto_close_and_send auto_close_and_send_min_quantity],
                description: 'what happens automatically when the end date is reached'
              },
              last_sent_mail: {
                type: :string,
                nullable: true,
                format: 'date-time',
                description: 'when the order was last emailed to the supplier'
              },
              supplier_has_email: {
                type: :boolean,
                description: 'whether the order can be emailed to the supplier'
              }
            }
          },
          OrderForUpdate: {
            type: :object,
            properties: {
              starts: { type: :string, format: 'date-time' },
              ends: { type: :string, format: 'date-time', nullable: true },
              boxfill: { type: :string, format: 'date-time', nullable: true },
              pickup: { type: :string, format: :date, nullable: true },
              note: { type: :string, nullable: true },
              end_action: { '$ref': '#/components/schemas/Order/properties/end_action' },
              article_ids: {
                type: :array,
                items: { type: :integer },
                description: "ids of the supplier's articles to offer; on create this defaults to all available articles"
              },
              ignore_warnings: {
                type: :boolean,
                description: 'on update, allow removing articles that members have already ordered'
              }
            }
          },
          OrderForCreate: {
            allOf: [
              { '$ref': '#/components/schemas/OrderForUpdate' },
              {
                type: :object,
                properties: { supplier_id: { type: :integer } },
                required: %w[supplier_id]
              }
            ]
          },
          Supplier: {
            type: :object,
            properties: {
              id: { type: :integer },
              name: { type: :string },
              delivery_days: { type: :string, nullable: true },
              min_order_quantity: { type: :string, nullable: true },
              note: { type: :string, nullable: true }
            },
            required: %w[id name]
          },
          ArticleForUpdate: {
            type: :object,
            properties: {
              name: { type: :string },
              article_category_id: { type: :integer },
              unit: { type: :string, description: 'amount of each unit, e.g. "100 g" or "kg"' },
              unit_quantity: { type: :integer, description: 'units can only be ordered from the supplier in multiples of unit_quantity' },
              note: { type: :string, nullable: true },
              manufacturer: { type: :string, nullable: true },
              origin: { type: :string, nullable: true },
              order_number: { type: :string, nullable: true },
              price: { type: :number, format: :float, description: 'net supplier price of one unit' },
              tax: { type: :number, format: :float, description: 'VAT percentage' },
              deposit: { type: :number, format: :float },
              availability: { type: :boolean }
            }
          },
          ArticleForCreate: {
            allOf: [
              { '$ref': '#/components/schemas/ArticleForUpdate' },
              {
                type: :object,
                properties: { supplier_id: { type: :integer } },
                required: %w[supplier_id name article_category_id unit price]
              }
            ]
          },
          ArticleDetail: {
            allOf: [
              { '$ref': '#/components/schemas/Article' },
              { '$ref': '#/components/schemas/ArticleForUpdate' },
              {
                type: :object,
                properties: {
                  fc_price: { type: :number, format: :float, description: 'foodcoop price of one unit (incl. tax, deposit and markup)' }
                }
              }
            ]
          },
          InvoiceForUpdate: {
            type: :object,
            properties: {
              number: { type: :string, nullable: true },
              date: { type: :string, format: :date, nullable: true },
              paid_on: { type: :string, format: :date, nullable: true, description: 'can only be set with the finance role' },
              note: { type: :string, nullable: true },
              amount: { type: :number, format: :float },
              deposit: { type: :number, format: :float },
              deposit_credit: { type: :number, format: :float },
              order_ids: { type: :array, items: { type: :integer } },
              delivery_ids: { type: :array, items: { type: :integer } }
            }
          },
          InvoiceForCreate: {
            allOf: [
              { '$ref': '#/components/schemas/InvoiceForUpdate' },
              {
                type: :object,
                properties: { supplier_id: { type: :integer } },
                required: %w[supplier_id]
              }
            ]
          },
          Invoice: {
            type: :object,
            properties: {
              id: { type: :integer },
              supplier_id: { type: :integer },
              supplier_name: { type: :string, nullable: true },
              number: { type: :string, nullable: true },
              date: { type: :string, format: :date, nullable: true },
              paid_on: { type: :string, format: :date, nullable: true },
              note: { type: :string, nullable: true },
              amount: { type: :number, format: :float },
              deposit: { type: :number, format: :float },
              deposit_credit: { type: :number, format: :float },
              created_at: { type: :string, format: 'date-time', nullable: true },
              created_by_user_id: { type: :integer, nullable: true },
              order_ids: { type: :array, items: { type: :integer } },
              can_edit: { type: :boolean, description: 'whether the current user may change this invoice' },
              attachments: {
                type: :array,
                items: {
                  type: :object,
                  properties: {
                    id: { type: :integer },
                    filename: { type: :string },
                    content_type: { type: :string },
                    byte_size: { type: :integer }
                  },
                  required: %w[id filename content_type byte_size]
                }
              }
            },
            required: %w[id supplier_id amount attachments]
          },
          Article: {
            type: :object,
            properties: {
              id: {
                type: :integer
              },
              name: {
                type: :string
              },
              supplier_id: {
                type: :integer,
                description: 'id of supplier, or 0 for stock articles'
              },
              supplier_name: {
                type: :string,
                nullable: true,
                description: 'name of the supplier, or null for stock articles'
              },
              unit: {
                type: :string,
                description: 'amount of each unit, e.g. "100 g" or "kg"'
              },
              unit_quantity: {
                type: :integer,
                description: 'units can only be ordered from the supplier in multiples of unit_quantity'
              },
              note: {
                type: :string,
                nullable: true,
                description: 'generic note'
              },
              manufacturer: {
                type: :string,
                nullable: true,
                description: 'manufacturer'
              },
              origin: {
                type: :string,
                nullable: true,
                description: 'origin, preferably (starting with a) 2-letter ISO country code'
              },
              article_category_id: {
                type: :integer,
                description: 'id of article category'
              },
              quantity_available: {
                type: :integer,
                description: 'number of units available (only present on stock articles)'
              }
            },
            required: %w[id name supplier_id supplier_name unit unit_quantity note manufacturer origin
                         article_category_id]
          },
          OrderArticle: {
            type: :object,
            properties: {
              id: {
                type: :integer
              },
              order_id: {
                type: :integer,
                description: 'id of order this order article belongs to'
              },
              price: {
                type: :number,
                format: :float,
                description: 'foodcoop price'
              },
              quantity: {
                type: :integer,
                description: 'number of units ordered by members'
              },
              tolerance: {
                type: :integer,
                description: 'number of extra units that members are willing to buy to fill a box'
              },
              units_to_order: {
                type: :integer,
                description: 'number of units to order from the supplier'
              },
              units_received: {
                type: :number,
                nullable: true,
                description: 'number of units delivered, as entered when receiving; null before'
              },
              result_manually_changed: {
                type: :boolean,
                description: "members' amounts were changed by hand; receiving is locked for this article"
              },
              article: {
                '$ref': '#/components/schemas/Article'
              }
            }
          },
          ArticleCategory: {
            type: :object,
            properties: {
              id: {
                type: :integer
              },
              name: {
                type: :string
              }
            },
            required: %w[id name]
          },
          FinancialTransaction: {
            allOf: [
              { '$ref': '#/components/schemas/FinancialTransactionForCreate' },
              {
                type: :object,
                properties: {
                  id: {
                    type: :integer
                  },
                  amount: {
                    type: :number,
                    format: :float,
                    nullable: true,
                    description: 'amount credited. Negative for a debit transaction, null for an incomplete transaction.'
                  },
                  financial_transaction_type_id: {
                    type: :integer,
                    description: 'id of the type of the transaction'
                  },
                  note: {
                    type: :string,
                    description: 'note entered with the transaction'
                  },
                  user_id: {
                    type: :integer,
                    nullable: true,
                    description: 'id of user who entered the transaction (may be <tt>null</tt> for deleted users or 0 for a system user)'
                  },
                  user_name: {
                    type: :string,
                    nullable: true,
                    description: 'name of user who entered the transaction (may be <tt>null</tt> or empty string for deleted users or system users)'
                  },
                  financial_transaction_type_name: {
                    type: :string,
                    description: 'name of the type of the transaction'
                  },
                  created_at: {
                    type: :string,
                    format: 'date-time',
                    description: 'when the transaction was entered'
                  }
                },
                required: %w[id user_id user_name financial_transaction_type_name created_at]
              }
            ]
          },
          FinancialTransactionForCreate: {
            type: :object,
            properties: {
              amount: {
                type: :number,
                format: :float,
                description: 'amount credited (negative for a debit transaction)'
              },
              financial_transaction_type_id:
              {
                type: :integer,
                description: 'id of the type of the transaction'
              },
              note: {
                type: :string,
                description: 'note entered with the transaction'
              }
            },
            required: %w[amount note user_id]
          },
          FinancialTransactionClass: {
            type: :object,
            properties: {
              id: {
                type: :integer
              },
              name: {
                type: :string
              }
            },
            required: %w[id name]
          },
          FinancialTransactionType: {
            type: :object,
            properties: {
              id: {
                type: :integer
              },
              name: {
                type: :string
              },
              name_short: {
                type: :string,
                nullable: true,
                description: 'short name (used for bank transfers)'
              },
              bank_account_id: {
                type: :integer,
                nullable: true,
                description: 'id of the bank account used for this transaction type'
              },
              bank_account_name: {
                type: :string,
                nullable: true,
                description: 'name of the bank account used for this transaction type'
              },
              bank_account_iban: {
                type: :string,
                nullable: true,
                description: 'IBAN of the bank account used for this transaction type'
              },
              financial_transaction_class_id: {
                type: :integer,
                description: 'id of the class of the transaction'
              },
              financial_transaction_class_name: {
                type: :string,
                description: 'name of the class of the transaction'
              }
            },
            required: %w[id name financial_transaction_class_id financial_transaction_class_name]
          },
          GroupOrderArticleForUpdate: {
            type: :object,
            properties: {
              quantity:
              {
                type: :integer,
                description: 'number of units ordered by the users ordergroup'
              },
              tolerance:
              {
                type: :integer,
                description: 'number of extra units the users ordergroup is willing to buy for filling a box'
              }
            }
          },
          GroupOrderArticleForCreate: {
            allOf: [
              { '$ref': '#/components/schemas/GroupOrderArticleForUpdate' },
              {
                type: :object,
                properties: {
                  order_article_id:
                  {
                    type: :integer,
                    description: 'id of order article'
                  }
                }
              }
            ]
          },
          GroupOrderArticle: {
            allOf: [
              { '$ref': '#/components/schemas/GroupOrderArticleForCreate' },
              {
                type: :object,
                properties: {
                  id: {
                    type: :integer
                  },
                  result: {
                    type: :number,
                    format: :float,
                    description: 'number of units the users ordergroup will receive or has received'
                  },
                  total_price:
                  {
                    type: :number,
                    format: :float,
                    description: 'total price of this group order article'
                  },
                  order_article_id:
                  {
                    type: :integer,
                    description: 'id of order article'
                  }
                },
                required: %w[order_article_id]
              }
            ]
          },
          q_ordered: {
            type: :object,
            properties: {
              ordered: {
                type: :string,
                enum: %w[member all supplier]
              }
            }
          },
          Meta: {
            type: :object,
            properties: {
              page: {
                type: :integer,
                description: 'page number of the returned collection'
              },
              per_page: {
                type: :integer,
                description: 'number of items per page'
              },
              total_pages: {
                type: :integer,
                description: 'total number of pages'
              },
              total_count: {
                type: :integer,
                description: 'total number of items in the collection'
              }
            },
            required: %w[page per_page total_pages total_count]
          },
          Navigation: {
            type: :array,
            items: {
              type: :object,
              properties: {
                name: {
                  type: :string,
                  description: 'title'
                },
                url: {
                  type: :string,
                  description: 'link'
                },
                items: {
                  '$ref': '#/components/schemas/Navigation'
                }
              },
              required: ['name'],
              minProperties: 2 # name+url or name+items
            }
          },
          Error: {
            type: :object,
            properties: {
              error: {
                type: :string,
                description: 'error code'
              },
              error_description: {
                type: :string,
                description: 'human-readable error message (localized)'
              }
            }
          },
          Error401: {
            type: :object,
            properties: {
              error: {
                type: :string,
                description: '<tt>unauthorized</tt>'
              },
              error_description: {
                '$ref': '#/components/schemas/Error/properties/error_description'
              }
            }
          },
          Error403: {
            type: :object,
            properties: {
              error: {
                type: :string,
                description: '<tt>forbidden</tt> or <tt>invalid_scope</tt>'
              },
              error_description: {
                '$ref': '#/components/schemas/Error/properties/error_description'
              }
            }
          },
          Error404: {
            type: :object,
            properties: {
              error: {
                type: :string,
                description: '<tt>not_found</tt>'
              },
              error_description: {
                '$ref': '#/components/schemas/Error/properties/error_description'
              }
            }
          },
          Error422: {
            type: :object,
            properties: {
              error: {
                type: :string,
                description: '<tt>unprocessable entity</tt>'
              },
              error_description: {
                '$ref': '#/components/schemas/Error/properties/error_description'
              }
            }
          }
        },
        securitySchemes: {
          oauth2: {
            type: :oauth2,
            flows: {
              implicit: {
                authorizationUrl: 'http://localhost:3000/f/oauth/authorize',
                scopes: {
                  'config:user': 'reading Foodsoft configuration for regular users',
                  'config:read': 'reading Foodsoft configuration values',
                  'config:write': 'reading and updating Foodsoft configuration values',
                  'finance:user': 'accessing your own financial transactions',
                  'finance:read': 'reading all financial transactions',
                  'finance:write': 'reading and creating financial transactions',
                  'user:read': 'reading your own user profile',
                  'user:write': 'reading and updating your own user profile',
                  'messages:read': 'reading messages you may see',
                  'messages:write': 'reading, sending, editing and deleting your messages',
                  'orders:read': 'reading orders',
                  'orders:write': 'opening, updating and finishing orders',
                  'group_orders:user': "managing your ordergroup's order",
                  'articles:read': 'reading articles of suppliers',
                  'articles:write': 'creating, updating and deleting articles',
                  'invoices:read': 'reading invoices and their attachments',
                  'invoices:write': 'creating and updating invoices, uploading attachments',
                  'suppliers:read': 'reading suppliers',
                  offline_access: 'retain access after user has logged out'
                }
              }
            }
          }
        }
      },
      servers: [
        {
          url: 'http://{defaultHost}/f/api/v1',
          variables: {
            defaultHost: {
              default: 'localhost:3000'
            }
          }
        }
      ],
      security: [
        oauth2: [
          'user:read'
        ]
      ]
    }
  }

  # Specify the format of the output Swagger file when running 'rswag:specs:swaggerize'.
  # The swagger_docs configuration option has the filename including format in
  # the key, this may want to be changed to avoid putting yaml in json files.
  # Defaults to json. Accepts ':json' and ':yaml'.
  config.swagger_format = :yaml
end
