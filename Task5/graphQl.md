```cs
type Query {
  client(id: string!): Client
  clients(
    filter: ClientFilter
    pagination: PaginationInput
  ): ClientConnection!
}

type Client {
  id: string!
  name: string!
  age: int32!  
  documents: [Document!]!  
  relatives: [Relative!]!
  fullGreeting: string!
}

type Document {
  id: string!
  type: string!
  number: string!
  issueDate: string!
  expiryDate: string!
}

type Relative {
  type: RelativeType!
  Person: Client!
  relationDescription: string!
}

enum RelativeType{
    Brother,
    Sister,
    Mother,
    Father,
    Wife,
    Husband
}

type Mutation {
  updateClient(id: string!, input: UpdateClientInput!): Client!
  addDocument(id: string!, input: DocumentInput!): Document!
  deleteDocument(id: string!): Boolean!
}

input UpdateClientInput {
  name: string
  age: int
}

input DocumentInput {
  type: string!
  number: string!
  issueDate: string!
  expiryDate: string!
}


schema {
  query: Query
  mutation: Mutation
}
```